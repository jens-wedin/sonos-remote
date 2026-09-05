import Foundation
import Testing
@testable import SonosKit

@Suite struct SocketFrameTests {
    @Test func subscribeFrameIsHeaderPlusEmptyBody() throws {
        let data = Subscription(namespace: "playback:1", scope: .group("G1")).frame(command: "subscribe")
        let array = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        #expect(array.count == 2)
        #expect(array[0]["namespace"] as? String == "playback:1")
        #expect(array[0]["command"] as? String == "subscribe")
        #expect(array[0]["groupId"] as? String == "G1")
        #expect(array[0]["playerId"] == nil)
        #expect(array[1].isEmpty)
    }

    @Test func playerAndHouseholdScopesUseTheRightKey() throws {
        let player = try JSONSerialization.jsonObject(with: Subscription(namespace: "playerVolume:1", scope: .player("P1")).frame(command: "subscribe")) as! [[String: Any]]
        #expect(player[0]["playerId"] as? String == "P1")
        let household = try JSONSerialization.jsonObject(with: Subscription(namespace: "groups:1", scope: .household).frame(command: "unsubscribe")) as! [[String: Any]]
        #expect(household[0]["householdId"] as? String == "local")
        #expect(household[0]["command"] as? String == "unsubscribe")
    }

    @Test func decodesTheCapturedEventSequence() throws {
        let events = try Fixtures.lines("events.jsonl").map { try SocketFrameDecoder.decode(Data($0.utf8)) }
        let gid = "RINCON_542A1B73A25001400:620674909"
        #expect(events.count == 13)
        #expect(events[0] == .subscribed(namespace: "playback:1", success: true))
        #expect(events[1] == .playbackStatus(groupID: gid, state: .playing))
        #expect(events[2] == .subscribed(namespace: "playbackMetadata:1", success: true))
        guard case .metadata(let metaGroup, let nowPlaying) = events[3] else { Issue.record("expected metadata"); return }
        #expect(metaGroup == gid)
        #expect(nowPlaying?.title == "Off the Wall")
        #expect(events[5] == .groupVolume(groupID: gid, volume: Volume(level: 5, muted: false, fixed: false)))
        #expect(events[7] == .playerVolume(playerID: "RINCON_542A1B73A25001400", volume: Volume(level: 2, muted: false, fixed: false)))
        guard case .groups(let groups, let players) = events[9] else { Issue.record("expected groups"); return }
        #expect(groups.count == 3)
        #expect(players.count == 4)
        #expect(groups.allSatisfy { $0.playbackState == nil })
        #expect(events[11] == .favoritesChanged)
        #expect(events[12] == .globalError(code: "ERROR_UNSUPPORTED_NAMESPACE"))
    }

    @Test func unknownTypeDoesNotThrow() throws {
        let frame = #"[{"namespace":"playback:1","type":"somethingNew","groupId":"G1"},{"x":1}]"#
        #expect(try SocketFrameDecoder.decode(Data(frame.utf8)) == .unknown(type: "somethingNew"))
    }

    @Test func malformedFrameThrows() {
        #expect(throws: (any Error).self) { try SocketFrameDecoder.decode(Data("not json".utf8)) }
        #expect(throws: (any Error).self) { try SocketFrameDecoder.decode(Data("[]".utf8)) }
    }
}
