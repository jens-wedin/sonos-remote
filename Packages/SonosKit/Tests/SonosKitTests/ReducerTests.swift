import Foundation
import Testing
@testable import SonosKit

@Suite struct ReducerTests {
    let gid = "RINCON_542A1B73A25001400:620674909"

    func topology() throws -> HouseholdEvent {
        let response = try JSONDecoder().decode(GroupsResponse.self, from: Fixtures.data("groups.json"))
        return .topology(groups: response.groups, players: response.players)
    }

    @Test func topologyBuildsSortedGroupsAndPlayers() throws {
        let snapshot = SnapshotReducer.reduce(HouseholdSnapshot(), try topology())
        #expect(snapshot.groups.map(\.name) == ["Elsas Sovrum", "Flyttbar + 1", "Sovrum"])
        #expect(snapshot.players.map(\.name) == ["Elsas Sovrum", "Flyttbar", "Sovrum", "Stereo"])
        let flyttbar = try #require(snapshot.group(gid))
        #expect(flyttbar.playbackState == .playing)
        #expect(flyttbar.volume == .silent)
        #expect(flyttbar.nowPlaying == nil)
        #expect(snapshot.player("RINCON_347E5C04E98101400")?.address == "192.168.1.105")
        #expect(snapshot.status == .discovering)
    }

    @Test func topologyWithoutPlaybackStatePreservesKnownState() throws {
        var snapshot = SnapshotReducer.reduce(HouseholdSnapshot(), try topology())
        snapshot = SnapshotReducer.reduce(snapshot, .groupVolume(groupID: gid, volume: Volume(level: 40, muted: true, fixed: false)))
        snapshot = SnapshotReducer.reduce(snapshot, .metadata(groupID: gid, nowPlaying: NowPlaying(title: "Song")))
        snapshot = SnapshotReducer.reduce(snapshot, .playerHasSub(playerID: "RINCON_347E5C04E98101400", hasSub: true))

        // Same groups, but as the websocket sends them: no playbackState.
        let eventGroups = try Fixtures.lines("events.jsonl").compactMap { line -> (groups: [WireGroup], players: [WirePlayer])? in
            if case .groups(let g, let p) = try SocketFrameDecoder.decode(Data(line.utf8)) { return (g, p) }
            return nil
        }.first
        let wire = try #require(eventGroups)
        let next = SnapshotReducer.reduce(snapshot, .topology(groups: wire.groups, players: wire.players))

        let flyttbar = try #require(next.group(gid))
        #expect(flyttbar.playbackState == .playing)
        #expect(flyttbar.volume.level == 40)
        #expect(flyttbar.nowPlaying?.title == "Song")
        #expect(next.player("RINCON_347E5C04E98101400")?.hasSub == true)
    }

    @Test func topologyChangeMovesPlayersAndDropsOldGroups() throws {
        let snapshot = SnapshotReducer.reduce(HouseholdSnapshot(), try topology())
        let regrouped: [WireGroup] = [
            WireGroup(id: "RINCON_542A1B73A25001400:1", name: "Flyttbar", coordinatorId: "RINCON_542A1B73A25001400", playbackState: nil, playerIds: ["RINCON_542A1B73A25001400"]),
            WireGroup(id: "RINCON_347E5C04E98101400:1", name: "Stereo", coordinatorId: "RINCON_347E5C04E98101400", playbackState: "PLAYBACK_STATE_PAUSED", playerIds: ["RINCON_347E5C04E98101400"]),
        ]
        let players = snapshot.players.map { WirePlayer(id: $0.id, name: $0.name, websocketUrl: "wss://\($0.address):1443/websocket/api") }
        let next = SnapshotReducer.reduce(snapshot, .topology(groups: regrouped, players: players))
        #expect(next.groups.map(\.name) == ["Flyttbar", "Stereo"])
        #expect(next.group(gid) == nil)
        #expect(next.group("RINCON_347E5C04E98101400:1")?.playbackState == .paused)
        #expect(next.group("RINCON_542A1B73A25001400:1")?.playbackState == .idle)
        #expect(next.players.count == 4)
    }

    @Test func groupScopedEventsUpdateOnlyTheirGroup() throws {
        var snapshot = SnapshotReducer.reduce(HouseholdSnapshot(), try topology())
        snapshot = SnapshotReducer.reduce(snapshot, .playbackStatus(groupID: gid, state: .paused))
        snapshot = SnapshotReducer.reduce(snapshot, .playbackStatus(groupID: "nope", state: .playing))
        #expect(snapshot.group(gid)?.playbackState == .paused)
        #expect(snapshot.groups.filter { $0.playbackState == .playing }.isEmpty)
    }

    @Test func playerVolumeFavoritesAndStatus() throws {
        var snapshot = SnapshotReducer.reduce(HouseholdSnapshot(), try topology())
        snapshot = SnapshotReducer.reduce(snapshot, .playerVolume(playerID: "RINCON_542A1B73A25001400", volume: Volume(level: 2, muted: false, fixed: false)))
        snapshot = SnapshotReducer.reduce(snapshot, .favorites([Favorite(id: "3", name: "P3")]))
        snapshot = SnapshotReducer.reduce(snapshot, .status(.ready))
        #expect(snapshot.playerVolumes["RINCON_542A1B73A25001400"]?.level == 2)
        #expect(snapshot.favorites.map(\.name) == ["P3"])
        #expect(snapshot.status == .ready)
    }

    @Test func playerRemovedCleansUpEverywhere() throws {
        var snapshot = SnapshotReducer.reduce(HouseholdSnapshot(), try topology())
        snapshot = SnapshotReducer.reduce(snapshot, .playerVolume(playerID: "RINCON_48A6B8194D2A01400", volume: Volume(level: 9, muted: false, fixed: false)))
        snapshot = SnapshotReducer.reduce(snapshot, .playerRemoved(playerID: "RINCON_48A6B8194D2A01400"))
        #expect(snapshot.player("RINCON_48A6B8194D2A01400") == nil)
        #expect(snapshot.groups.map(\.name) == ["Elsas Sovrum", "Flyttbar + 1"])
        #expect(snapshot.playerVolumes["RINCON_48A6B8194D2A01400"] == nil)

        snapshot = SnapshotReducer.reduce(snapshot, .playerRemoved(playerID: "RINCON_347E5C04E98101400"))
        #expect(snapshot.group(gid)?.playerIDs == ["RINCON_542A1B73A25001400"])
    }
}
