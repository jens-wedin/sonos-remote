import Foundation
import Observation
import SonosKit

extension PlaybackState {
    /// Playing or about to play; these groups sort to the top of the panel.
    var isActive: Bool { self == .playing || self == .buffering }
}

@MainActor @Observable
final class AppState {
    private(set) var snapshot = HouseholdSnapshot()

    /// Groups for display: the ones playing (or about to) first, then the rest, each tier by name.
    var orderedGroups: [Group] {
        snapshot.groups.sorted { lhs, rhs in
            let lhsActive = lhs.playbackState.isActive
            let rhsActive = rhs.playbackState.isActive
            if lhsActive != rhsActive { return lhsActive }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    /// The one room every screen shows. Never nil while groups exist.
    var selectedGroupID: String? {
        didSet { defaults.set(selectedGroupID, forKey: Self.selectedGroupKey) }
    }
    var selectedGroup: Group? { selectedGroupID.flatMap { snapshot.group($0) } }

    // Navigation and per-screen state.
    private(set) var screen: Screen = .main
    var favoritesSearch = ""
    var favoritesTargetGroupID: String?
    var soundPlayerID: String?
    var eqByPlayer: [String: EQSettings] = [:]
    var rowErrors: [String: String] = [:]

    /// Increments once per second while the panel is visible and the selected group is playing;
    /// views read it so the progress bar re-renders between speaker reports.
    private(set) var tick = 0

    private(set) var household: Household
    private let defaults: UserDefaults
    private let clearDelay: Duration
    private let tickInterval: Duration
    private var consumeTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?
    private var panelPresented = false
    private var resolvedInitialSelection = false
    private var errorGeneration: [String: Int] = [:]
    private static let selectedGroupKey = "selectedGroupID"

    init(household: Household, defaults: UserDefaults = .standard, clearDelay: Duration = .seconds(3), tickInterval: Duration = .seconds(1)) {
        self.household = household
        self.defaults = defaults
        self.clearDelay = clearDelay
        self.tickInterval = tickInterval
        self.selectedGroupID = defaults.string(forKey: Self.selectedGroupKey)
    }

    static func live() -> AppState {
        let transport = URLSessionTransport(trustStore: TrustStore(pinStore: UserDefaultsPinStore()))
        let household = Household(discovery: BonjourDiscovery(), transport: transport, trustStore: transport.trustStore)
        return AppState(household: household)
    }

    // MARK: Lifecycle

    func start() {
        guard consumeTask == nil else { return }
        consumeTask = Task { [household] in
            await household.start()
            for await snapshot in await household.snapshots() {
                self.apply(snapshot)
            }
        }
    }

    /// Tears the household down and starts discovery again (Settings → refresh, "No Sonos found" → Retry).
    func retryDiscovery() {
        consumeTask?.cancel()
        consumeTask = nil
        resolvedInitialSelection = false
        let old = household
        Task { await old.stop() }
        let transport = URLSessionTransport(trustStore: TrustStore(pinStore: UserDefaultsPinStore()))
        household = Household(discovery: BonjourDiscovery(), transport: transport, trustStore: transport.trustStore)
        snapshot = HouseholdSnapshot()
        rowErrors = [:]
        updateTicking()
        start()
    }

    func apply(_ snapshot: HouseholdSnapshot) {
        self.snapshot = snapshot
        guard !snapshot.groups.isEmpty else { updateTicking(); return }
        let stillExists = selectedGroupID.map { id in snapshot.groups.contains { $0.id == id } } ?? false
        if !stillExists || !resolvedInitialSelection {
            selectedGroupID = SelectionPolicy.resolve(remembered: selectedGroupID, groups: snapshot.groups)
        }
        resolvedInitialSelection = true
        // The Favorites picker targets one group; if it disappears (regrouped from the Sonos
        // app while the screen is open), fall back to the room every screen shows.
        if let target = favoritesTargetGroupID, snapshot.group(target) == nil {
            favoritesTargetGroupID = selectedGroupID
        }
        // The Sound screen's picker is over ALL players, not just the selected group's (spec
        // §5), so a player outside the selected group is a legitimate choice; only re-anchor
        // when the chosen player no longer exists at all.
        if soundPlayerID.flatMap(snapshot.player) == nil {
            soundPlayerID = selectedGroup?.coordinatorID
        }
        updateTicking()
    }

    // MARK: Selection and navigation

    func select(_ groupID: String) {
        guard snapshot.group(groupID) != nil else { return }
        selectedGroupID = groupID
        soundPlayerID = snapshot.group(groupID)?.coordinatorID
        updateTicking()
    }

    /// Header icons: tapping the active screen's icon returns to main.
    func show(_ target: Screen) {
        let next: Screen = (target == screen) ? .main : target
        if next == .favorites { favoritesTargetGroupID = selectedGroupID; favoritesSearch = "" }
        if next == .sound { soundPlayerID = selectedGroup?.coordinatorID }
        screen = next
    }

    func back() { screen = .main }

    func setPanelPresented(_ presented: Bool) {
        panelPresented = presented
        updateTicking()
    }

    private func updateTicking() {
        let shouldTick = panelPresented && selectedGroup?.playbackState == .playing
        if shouldTick, tickTask == nil {
            tickTask = Task { [tickInterval] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: tickInterval)
                    if Task.isCancelled { break }
                    self.tick &+= 1
                }
            }
        } else if !shouldTick, let task = tickTask {
            task.cancel()
            tickTask = nil
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
    func setShuffle(_ on: Bool, group id: String) { run(id) { try await self.household.setShuffle(on, group: id) } }
    func setRepeat(_ on: Bool, group id: String) { run(id) { try await self.household.setRepeat(on, group: id) } }

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

    func applyPreset(_ preset: TonePreset, player: String) {
        guard let current = eqByPlayer[player] else { return }
        updateEQ(preset.applied(to: current), player: player)
    }

    func resetTone(player: String) {
        guard var eq = eqByPlayer[player] else { return }
        eq.bass = 0
        eq.treble = 0
        if eq.subGain != nil { eq.subGain = 0 }
        updateEQ(eq, player: player)
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
        Task { [clearDelay] in
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
            case .http, .decoding, .badAddress: return "Couldn't reach the speaker."
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
