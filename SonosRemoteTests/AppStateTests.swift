import Foundation
import Testing
import SonosKit
@testable import SonosRemote

@MainActor
@Suite struct AppStateTests {
    func makeAppState(clearDelay: Duration = .seconds(3)) -> AppState {
        let transport = URLSessionTransport()
        let household = Household(discovery: BonjourDiscovery(), transport: transport)
        return AppState(
            household: household,
            defaults: UserDefaults(suiteName: "AppStateTests-\(UUID())")!,
            clearDelay: clearDelay
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
        #expect(appState.openGroupID == "b")
    }

    @Test func openRowIsKeptWhileItExists() {
        let appState = makeAppState()
        appState.apply(snapshot([group("a", .idle), group("b", .idle)]))
        #expect(appState.openGroupID == "a")
        appState.apply(snapshot([group("a", .idle), group("b", .playing)]))
        #expect(appState.openGroupID == "a")
    }

    @Test func vanishedOpenRowReresolves() {
        let appState = makeAppState()
        appState.apply(snapshot([group("a", .idle), group("b", .idle)]))
        #expect(appState.openGroupID == "a")
        appState.apply(snapshot([group("b", .playing), group("c", .idle)]))
        #expect(appState.openGroupID == "b")
    }

    @Test func userClosedRowStaysClosedWithoutTopologyChange() {
        let appState = makeAppState()
        let groups = [group("a", .idle), group("b", .playing)]
        appState.apply(snapshot(groups))
        #expect(appState.openGroupID == "b")
        appState.toggleRow("b")
        #expect(appState.openGroupID == nil)

        appState.apply(snapshot([group("a", .playing), group("b", .idle)]))
        #expect(appState.openGroupID == nil)
    }

    @Test func userClosedRowReopensOnTopologyChange() {
        let appState = makeAppState()
        let groups = [group("a", .idle), group("b", .playing)]
        appState.apply(snapshot(groups))
        #expect(appState.openGroupID == "b")
        appState.toggleRow("b")
        #expect(appState.openGroupID == nil)

        let newGroups = [group("x", .idle), group("y", .playing)]
        appState.apply(snapshot(newGroups))
        #expect(appState.openGroupID != nil)
        #expect(appState.openGroupID == RowOpenPolicy.resolve(remembered: nil, groups: newGroups))
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
