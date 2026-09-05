import Foundation
import Observation
import SonosKit

extension PlaybackState {
    /// Playing or about to play; these groups sort to the top of the panel.
    var isActive: Bool { self == .playing || self == .buffering }
}

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

    /// Groups for display: the ones playing (or about to) first, then the rest, each tier by name.
    /// The reducer keeps `snapshot.groups` in plain name order so this is purely presentational.
    var orderedGroups: [Group] {
        snapshot.groups.sorted { lhs, rhs in
            let lhsActive = lhs.playbackState.isActive
            let rhsActive = rhs.playbackState.isActive
            if lhsActive != rhsActive { return lhsActive }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
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
    private let clearDelay: Duration
    private var consumeTask: Task<Void, Never>?
    private var resolvedInitialRow = false
    /// Group ids seen in the last applied snapshot. Used to tell a topology change (which may
    /// reopen a user-closed row) apart from a plain state update (which must not).
    private var lastGroupIDs: Set<String> = []
    /// Bumped on every `report` for a row so a stale delayed clear (from an earlier error that
    /// happens to render the same message) can't clear a newer one.
    private var errorGeneration: [String: Int] = [:]
    private static let openGroupKey = "openGroupID"

    init(household: Household, defaults: UserDefaults = .standard, clearDelay: Duration = .seconds(3)) {
        self.household = household
        self.defaults = defaults
        self.clearDelay = clearDelay
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

    /// Tears the household down and starts discovery again (used by the "No Sonos found" state).
    func retryDiscovery() {
        consumeTask?.cancel()
        consumeTask = nil
        resolvedInitialRow = false
        let old = household
        Task { await old.stop() }
        let transport = URLSessionTransport()
        household = Household(discovery: BonjourDiscovery(), transport: transport, trustStore: transport.trustStore)
        snapshot = HouseholdSnapshot()
        start()
    }

    func apply(_ snapshot: HouseholdSnapshot) {
        self.snapshot = snapshot
        guard !snapshot.groups.isEmpty else { return }
        let groupIDs = Set(snapshot.groups.map(\.id))
        let topologyChanged = groupIDs != lastGroupIDs
        let openStillExists = openGroupID.map { id in snapshot.groups.contains { $0.id == id } } ?? false
        let shouldResolve: Bool
        if openStillExists {
            // Keep the open row.
            shouldResolve = false
        } else if openGroupID != nil {
            // The open row vanished; always resolve to a new one.
            shouldResolve = true
        } else {
            // Nothing is open: resolve on the very first snapshot, or once the topology has
            // changed since the user closed the row. Otherwise the closed state persists.
            shouldResolve = !resolvedInitialRow || topologyChanged
        }
        if shouldResolve {
            openGroupID = RowOpenPolicy.resolve(remembered: openGroupID, groups: snapshot.groups)
        }
        resolvedInitialRow = true
        lastGroupIDs = groupIDs
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

    /// Internal (not private) so tests can exercise the delayed-clear behavior directly.
    func report(_ groupID: String, _ error: any Error) {
        let generation = (errorGeneration[groupID] ?? 0) + 1
        errorGeneration[groupID] = generation
        rowErrors[groupID] = Self.message(for: error)
        Task {
            try? await Task.sleep(for: clearDelay)
            if errorGeneration[groupID] == generation { rowErrors[groupID] = nil }
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
