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

    @Test func retryDiscoveryReplacesHouseholdAndResetsSnapshot() {
        let appState = makeAppState()
        let originalHousehold = appState.household
        appState.apply(snapshot([group("a", .idle), group("b", .playing)]))
        #expect(appState.snapshot.status == .ready)

        appState.retryDiscovery()

        #expect(appState.household !== originalHousehold)
        #expect(appState.snapshot.status == .discovering)
        #expect(appState.snapshot.groups.isEmpty)
    }
}
