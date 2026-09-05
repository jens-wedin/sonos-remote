import Foundation
import Observation
import SonosKit

enum OpenRowTab: String, CaseIterable, Identifiable {
    case favorites, eq, group
    var id: String { rawValue }
    var title: String {
        switch self {
        case .favorites: "Favorites"
        case .eq: "EQ"
        case .group: "Group"
        }
    }
}

@MainActor @Observable
final class AppState {
    private(set) var snapshot = HouseholdSnapshot()
    /// The one open row. nil only when the user closed it or nothing is discovered.
    var openGroupID: String? {
        didSet { defaults.set(openGroupID, forKey: Self.openGroupKey) }
    }
    var selectedTab: OpenRowTab = .favorites
    /// Player whose EQ the EQ tab shows (matters for multi-player groups).
    var eqPlayerID: String?
    var eqByPlayer: [String: EQSettings] = [:]
    var rowErrors: [String: String] = [:]

    /// Replaced by `retryDiscovery()` (Task 18); everything else reads it at call time.
    private(set) var household: Household
    private let defaults: UserDefaults
    private var consumeTask: Task<Void, Never>?
    private var resolvedInitialRow = false
    private static let openGroupKey = "openGroupID"

    init(household: Household, defaults: UserDefaults = .standard) {
        self.household = household
        self.defaults = defaults
        self.openGroupID = defaults.string(forKey: Self.openGroupKey)
    }

    static func live() -> AppState {
        let transport = URLSessionTransport()
        let household = Household(discovery: BonjourDiscovery(), transport: transport, trustStore: transport.trustStore)
        return AppState(household: household)
    }

    func start() {
        guard consumeTask == nil else { return }
        consumeTask = Task { [household] in
            await household.start()
            for await snapshot in await household.snapshots() {
                self.apply(snapshot)
            }
        }
    }

    func apply(_ snapshot: HouseholdSnapshot) {
        self.snapshot = snapshot
        guard !snapshot.groups.isEmpty else { return }
        let openStillExists = openGroupID.map { id in snapshot.groups.contains { $0.id == id } } ?? false
        if !openStillExists && (!resolvedInitialRow || openGroupID != nil) {
            openGroupID = RowOpenPolicy.resolve(remembered: openGroupID, groups: snapshot.groups)
        }
        resolvedInitialRow = true
        if let open = openGroupID, let group = snapshot.group(open), !group.playerIDs.contains(eqPlayerID ?? "") {
            eqPlayerID = group.coordinatorID
        }
    }

    // MARK: Row state

    func toggleRow(_ groupID: String) {
        if openGroupID == groupID {
            openGroupID = nil
        } else {
            openGroupID = groupID
            eqPlayerID = snapshot.group(groupID)?.coordinatorID
        }
    }

    // MARK: Commands (fire and forget with inline error reporting)

    func togglePlayPause(group id: String) {
        guard let group = snapshot.group(id) else { return }
        if group.playbackState == .playing { pause(group: id) } else { play(group: id) }
    }

    func play(group id: String) { run(id) { try await self.household.play(group: id) } }
    func pause(group id: String) { run(id) { try await self.household.pause(group: id) } }
    func next(group id: String) { run(id) { try await self.household.next(group: id) } }
    func previous(group id: String) { run(id) { try await self.household.previous(group: id) } }

    func setGroupVolume(_ level: Int, group id: String) { run(id) { try await self.household.setGroupVolume(level, group: id) } }
    func setGroupMuted(_ muted: Bool, group id: String) { run(id) { try await self.household.setGroupMuted(muted, group: id) } }

    func setPlayerVolume(_ level: Int, player: String) {
        run(snapshot.group(containing: player)?.id ?? player) { try await self.household.setPlayerVolume(level, player: player) }
    }

    func setPlayerMuted(_ muted: Bool, player: String) {
        run(snapshot.group(containing: player)?.id ?? player) { try await self.household.setPlayerMuted(muted, player: player) }
    }

    func playFavorite(_ favoriteID: String, group id: String) { run(id) { try await self.household.playFavorite(favoriteID, group: id) } }

    func setMembership(of player: String, inGroup id: String, member: Bool) {
        guard let group = snapshot.group(id) else { return }
        var members = group.playerIDs
        if member, !members.contains(player) { members.append(player) }
        if !member { members.removeAll { $0 == player } }
        guard members != group.playerIDs, !members.isEmpty else { return }
        let newMembers = members
        run(id) { try await self.household.setGroupMembers(newMembers, group: id) }
    }

    func loadEQ(player: String) {
        Task {
            do { eqByPlayer[player] = try await household.eq(player: player) }
            catch { report(snapshot.group(containing: player)?.id ?? player, error) }
        }
    }

    func updateEQ(_ eq: EQSettings, player: String) {
        eqByPlayer[player] = eq
        run(snapshot.group(containing: player)?.id ?? player) { try await self.household.setEQ(eq, player: player) }
    }

    // MARK: Errors

    private func run(_ groupID: String, _ operation: @escaping @Sendable () async throws -> Void) {
        Task {
            do { try await operation() }
            catch { report(groupID, error) }
        }
    }

    private func report(_ groupID: String, _ error: any Error) {
        rowErrors[groupID] = Self.message(for: error)
        Task {
            try? await Task.sleep(for: .seconds(3))
            if rowErrors[groupID] == Self.message(for: error) { rowErrors[groupID] = nil }
        }
    }

    static func message(for error: any Error) -> String {
        switch error {
        case let apiError as LocalAPIError:
            switch apiError {
            case .unauthorized, .invalidAPIKey: return "Not authorized. Check the Sonos app's connection security settings."
            case .groupGone, .coordinatorMoved: return "That group changed. Refreshing."
            case .http, .decoding: return "Couldn't reach the speaker."
            }
        case is HouseholdError:
            return "That room is no longer available."
        case is UPnPError:
            return "The speaker rejected the EQ change."
        default:
            return "Couldn't reach the speaker."
        }
    }
}
