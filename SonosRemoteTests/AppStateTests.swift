import Foundation
import Testing
import SonosKit
@testable import SonosRemote

@MainActor
@Suite struct AppStateTests {
    func makeAppState(clearDelay: Duration = .seconds(3), tickInterval: Duration = .seconds(1)) -> AppState {
        let transport = URLSessionTransport()
        let household = Household(discovery: BonjourDiscovery(), transport: transport)
        return AppState(
            household: household,
            defaults: UserDefaults(suiteName: "AppStateTests-\(UUID())")!,
            clearDelay: clearDelay,
            tickInterval: tickInterval
        )
    }

    func group(_ id: String, _ state: PlaybackState) -> Group {
        Group(id: id, name: id, coordinatorID: id, playerIDs: [id], playbackState: state, volume: .silent, nowPlaying: nil)
    }

    func snapshot(_ groups: [Group]) -> HouseholdSnapshot {
        HouseholdSnapshot(status: .ready, groups: groups, players: [])
    }

    @Test func orderedGroupsPutPlayingGroupsFirstThenAlphabetical() {
        let appState = makeAppState()
        appState.apply(snapshot([
            group("Sovrum", .idle),
            group("Stereo", .playing),
            group("Elsas Sovrum", .paused),
            group("Flyttbar", .buffering),
        ]))
        #expect(appState.orderedGroups.map(\.id) == ["Flyttbar", "Stereo", "Elsas Sovrum", "Sovrum"])
    }

    @Test func firstSnapshotOpensPlayingGroup() {
        let appState = makeAppState()
        appState.apply(snapshot([group("a", .idle), group("b", .playing)]))
        #expect(appState.selectedGroupID == "b")
    }

    @Test func openRowIsKeptWhileItExists() {
        let appState = makeAppState()
        appState.apply(snapshot([group("a", .idle), group("b", .idle)]))
        #expect(appState.selectedGroupID == "a")
        appState.apply(snapshot([group("a", .idle), group("b", .playing)]))
        #expect(appState.selectedGroupID == "a")
    }

    @Test func vanishedOpenRowReresolves() {
        let appState = makeAppState()
        appState.apply(snapshot([group("a", .idle), group("b", .idle)]))
        #expect(appState.selectedGroupID == "a")
        appState.apply(snapshot([group("b", .playing), group("c", .idle)]))
        #expect(appState.selectedGroupID == "b")
    }

    @Test func selectingAnotherGroupChangesTheSelection() {
        let appState = makeAppState()
        appState.apply(snapshot([group("a", .idle), group("b", .playing)]))
        appState.select("a")
        #expect(appState.selectedGroupID == "a")
        appState.apply(snapshot([group("a", .idle), group("b", .playing)]))
        #expect(appState.selectedGroupID == "a")
    }

    @Test func screensSwitchAndBackReturnsToMain() {
        let appState = makeAppState()
        #expect(appState.screen == .main)
        appState.show(.sound)
        #expect(appState.screen == .sound)
        appState.show(.sound)
        #expect(appState.screen == .main, "tapping the active screen's icon returns to main")
        appState.show(.favorites)
        appState.back()
        #expect(appState.screen == .main)
    }

    @Test func openingFavoritesTargetsTheSelectedRoomAndSoundTargetsItsCoordinator() {
        let appState = makeAppState()
        appState.apply(snapshot([Group(id: "g", name: "g", coordinatorID: "p1", playerIDs: ["p1", "p2"], playbackState: .playing, volume: .silent, nowPlaying: nil)]))
        appState.show(.favorites)
        #expect(appState.favoritesTargetGroupID == "g")
        appState.show(.sound)
        #expect(appState.soundPlayerID == "p1")
    }

    @Test func soundPlayerPersistsOutsideTheSelectedGroupUntilItVanishes() {
        let appState = makeAppState()
        let g = Group(id: "g", name: "g", coordinatorID: "p1", playerIDs: ["p1", "p2"], playbackState: .idle, volume: .silent, nowPlaying: nil)
        let h = Group(id: "h", name: "h", coordinatorID: "p3", playerIDs: ["p3"], playbackState: .idle, volume: .silent, nowPlaying: nil)
        let players = [
            Player(id: "p1", name: "p1", address: "10.0.0.1", hasSub: false),
            Player(id: "p2", name: "p2", address: "10.0.0.2", hasSub: false),
            Player(id: "p3", name: "p3", address: "10.0.0.3", hasSub: false),
        ]
        appState.apply(HouseholdSnapshot(status: .ready, groups: [g, h], players: players))
        appState.select("g")
        appState.soundPlayerID = "p3"

        // p3's group ("h") is still around, so picking it (a legitimate cross-group choice
        // on the Sound screen) must survive an unrelated snapshot, not snap back to "g".
        appState.apply(HouseholdSnapshot(status: .ready, groups: [g, h], players: players))
        #expect(appState.soundPlayerID == "p3")

        // p3 (and its group) is gone: re-anchor to the selected group's coordinator.
        appState.apply(HouseholdSnapshot(status: .ready, groups: [g], players: Array(players.prefix(2))))
        #expect(appState.soundPlayerID == "p1")
    }

    @Test func favoritesTargetReresolvesWhenItsGroupVanishes() {
        let appState = makeAppState()
        appState.apply(snapshot([group("a", .idle), group("b", .idle)]))
        appState.select("a")
        appState.show(.favorites)
        #expect(appState.favoritesTargetGroupID == "a")

        appState.apply(snapshot([group("b", .idle), group("c", .idle)]))
        #expect(appState.selectedGroupID == "b")
        #expect(appState.favoritesTargetGroupID == "b")
    }

    @Test func tickRunsOnlyWhilePresentedAndPlaying() async throws {
        let appState = makeAppState(tickInterval: .milliseconds(20))
        appState.apply(snapshot([group("a", .playing)]))
        appState.setPanelPresented(true)
        try await Task.sleep(for: .milliseconds(120))
        #expect(appState.tick >= 3)
        appState.setPanelPresented(false)
        let frozen = appState.tick
        try await Task.sleep(for: .milliseconds(80))
        #expect(appState.tick == frozen)
    }

    @Test func tickFreezesWhenTheSelectedGroupDisappears() async throws {
        let appState = makeAppState(tickInterval: .milliseconds(20))
        appState.apply(snapshot([group("a", .playing)]))
        appState.setPanelPresented(true)
        try await Task.sleep(for: .milliseconds(120))
        #expect(appState.tick >= 3)
        appState.apply(snapshot([]))
        let frozen = appState.tick
        try await Task.sleep(for: .milliseconds(80))
        #expect(appState.tick == frozen)
    }

    @Test func repeatedIdenticalErrorsKeepTheBannerUntilTheLastOneExpires() async throws {
        let appState = makeAppState(clearDelay: .milliseconds(200))
        let groupID = "g1"

        appState.report(groupID, HouseholdError.unknownGroup)
        try await Task.sleep(for: .milliseconds(100))
        appState.report(groupID, HouseholdError.unknownGroup)

        try await Task.sleep(for: .milliseconds(150))
        #expect(appState.rowErrors[groupID] != nil)

        try await Task.sleep(for: .milliseconds(150))
        #expect(appState.rowErrors[groupID] == nil)
    }

    @Test func applyPresetWritesBassAndTrebleAndKeepsLoudnessAndSub() {
        let appState = makeAppState()
        appState.eqByPlayer["p1"] = EQSettings(bass: 5, treble: -5, loudness: true, subGain: 4)
        appState.applyPreset(.warm, player: "p1")
        let eq = appState.eqByPlayer["p1"]
        #expect(eq?.bass == TonePreset.warm.bass)
        #expect(eq?.treble == TonePreset.warm.treble)
        #expect(eq?.loudness == true)
        #expect(eq?.subGain == 4)
    }

    @Test func resetToneZeroesBassTrebleAndSubWhenThePlayerHasASub() {
        let appState = makeAppState()
        appState.eqByPlayer["p1"] = EQSettings(bass: 5, treble: -5, loudness: true, subGain: 4)
        appState.resetTone(player: "p1")
        let eq = appState.eqByPlayer["p1"]
        #expect(eq?.bass == 0)
        #expect(eq?.treble == 0)
        #expect(eq?.subGain == 0)
    }

    @Test func resetToneLeavesSubNilWhenThePlayerHasNoSub() {
        let appState = makeAppState()
        appState.eqByPlayer["p1"] = EQSettings(bass: 5, treble: -5, loudness: true, subGain: nil)
        appState.resetTone(player: "p1")
        let eq = appState.eqByPlayer["p1"]
        #expect(eq?.bass == 0)
        #expect(eq?.treble == 0)
        #expect(eq?.subGain == nil)
    }

    @Test func showingFavoritesClearsTheSearchField() {
        let appState = makeAppState()
        appState.favoritesSearch = "jazz"
        appState.show(.favorites)
        #expect(appState.favoritesSearch == "")
    }

    @Test func selectingAnUnknownGroupLeavesTheSelectionUnchanged() {
        let appState = makeAppState()
        appState.apply(snapshot([group("a", .idle), group("b", .playing)]))
        appState.select("a")
        appState.select("unknown")
        #expect(appState.selectedGroupID == "a")
    }

    @Test func retryDiscoveryReplacesHouseholdAndResetsSnapshot() {
        let appState = makeAppState()
        let originalHousehold = appState.household
        appState.apply(snapshot([group("a", .idle), group("b", .playing)]))
        #expect(appState.status == .ready)

        appState.retryDiscovery()

        #expect(appState.household !== originalHousehold)
        #expect(appState.status == .discovering)
        #expect(appState.groups.isEmpty)
        #expect(appState.orderedGroups.isEmpty)
    }

    @Test func orderedGroupsIsRecomputedOnlyWhenGroupsChange() {
        let appState = makeAppState()
        appState.apply(snapshot([group("b", .idle), group("a", .playing)]))
        #expect(appState.orderedGroups.map(\.id) == ["a", "b"])
        appState.apply(snapshot([group("b", .playing), group("a", .idle)]))
        #expect(appState.orderedGroups.map(\.id) == ["b", "a"])
    }
}
