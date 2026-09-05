import Foundation
import Testing
@testable import SonosKit

@Suite struct HouseholdTests {
    let gid = "RINCON_542A1B73A25001400:620674909"
    let stereo = DiscoveredPlayer(id: "RINCON_347E5C04E98101400", address: "192.168.1.105", householdID: "HH")

    struct Harness {
        let discovery = FakeDiscovery()
        let transport = FakeTransport()
        let trust = TrustStore()
        let household: Household

        init(timeout: Duration = .seconds(5), backoff: Backoff = Backoff(base: .milliseconds(1), max: .milliseconds(5), jitter: 0)) {
            transport.respond(whenPathContains: "/households/local/groups", body: Fixtures.data("groups.json"))
            transport.respond(whenPathContains: "/households/local/favorites", body: Fixtures.data("favorites.json"))
            transport.respond(whenPathContains: "RenderingControl", body: Data(SOAP.envelope(action: "GetEQResponse", arguments: [("CurrentValue", "0")]).utf8))
            var configuration = Household.Configuration()
            configuration.discoveryTimeout = timeout
            configuration.backoff = backoff
            household = Household(discovery: discovery, transport: transport, trustStore: trust, configuration: configuration)
        }

        func startAndDiscover(_ player: DiscoveredPlayer) async throws -> HouseholdSnapshot {
            let stream = await household.snapshots()
            await household.start()
            discovery.emit(.found(player))
            for await snapshot in stream where snapshot.status == .ready && snapshot.favorites.count == 1 {
                return snapshot
            }
            throw WaitTimeout()
        }
    }

    @Test func discoveryLeadsToReadySnapshotSocketsAndSubscriptions() async throws {
        let h = Harness()
        let ready = try await h.startAndDiscover(stereo)
        #expect(ready.groups.map(\.name) == ["Elsas Sovrum", "Flyttbar + 1", "Sovrum"])
        #expect(ready.favorites.map(\.name) == ["P3"])
        #expect(h.trust.shouldTrust(host: "192.168.1.216"))
        try await waitUntil { h.transport.socketCount == 4 }
        let flyttbar = try #require(h.transport.socket(forHost: "192.168.1.216"))
        try await waitUntil { flyttbar.sentText.count == 4 }
        #expect(flyttbar.sentText.contains { $0.contains(#""namespace":"playbackMetadata:1""#) && $0.contains(gid) })
        let stereoSocket = try #require(h.transport.socket(forHost: "192.168.1.105"))
        try await waitUntil { stereoSocket.sentText.count == 3 }
        #expect(stereoSocket.sentText.contains { $0.contains(#""namespace":"groups:1""#) })
        // One SubCrossover probe per player.
        try await waitUntil { h.transport.requests(matching: "RenderingControl").count == 4 }
        await h.household.stop()
    }

    @Test func socketEventsUpdateTheSnapshot() async throws {
        let h = Harness()
        _ = try await h.startAndDiscover(stereo)
        try await waitUntil { h.transport.socket(forHost: "192.168.1.216") != nil }
        let socket = try #require(h.transport.socket(forHost: "192.168.1.216"))
        socket.push(#"[{"namespace":"groupVolume:1","type":"groupVolume","groupId":"\#(gid)"},{"volume":33,"muted":true,"fixed":false}]"#)
        try await waitUntil { await h.household.current.group(gid)?.volume == Volume(level: 33, muted: true, fixed: false) }
        socket.push(#"[{"namespace":"playerVolume:1","type":"playerVolume","playerId":"RINCON_542A1B73A25001400"},{"volume":9,"muted":false,"fixed":false}]"#)
        try await waitUntil { await h.household.current.playerVolumes["RINCON_542A1B73A25001400"]?.level == 9 }
        await h.household.stop()
    }

    @Test func groupCommandsGoToTheCoordinator() async throws {
        let h = Harness()
        _ = try await h.startAndDiscover(stereo)
        try await h.household.play(group: gid)
        try await h.household.setGroupVolume(21, group: gid)
        try await h.household.setPlayerVolume(7, player: "RINCON_48A6B8194D2A01400")
        try await h.household.playFavorite("3", group: gid)
        try await h.household.setGroupMembers(["RINCON_542A1B73A25001400"], group: gid)
        let posts = h.transport.requests.filter { $0.method == "POST" && $0.url.port == 1443 }.map { $0.url.absoluteString }
        #expect(posts == [
            "https://192.168.1.216:1443/api/v1/groups/\(gid)/playback/play",
            "https://192.168.1.216:1443/api/v1/groups/\(gid)/groupVolume",
            "https://192.168.1.28:1443/api/v1/players/RINCON_48A6B8194D2A01400/playerVolume",
            "https://192.168.1.216:1443/api/v1/groups/\(gid)/favorites",
            "https://192.168.1.216:1443/api/v1/groups/\(gid)/groups/setGroupMembers",
        ])
        await #expect(throws: HouseholdError.unknownGroup) { try await h.household.pause(group: "nope") }
        await h.household.stop()
    }

    @Test func coordinatorMovedRefetchesTopologyAndRetries() async throws {
        let h = Harness()
        _ = try await h.startAndDiscover(stereo)
        h.transport.respond(whenPathContains: "/playback/pause", sequence: [
            StubResponse(status: 404, body: Fixtures.data("error_404_coordinator_moved.json")),
            StubResponse(),
        ])
        let groupsBefore = h.transport.requests(matching: "/households/local/groups").count
        try await h.household.pause(group: gid)
        #expect(h.transport.requests(matching: "/playback/pause").count == 2)
        #expect(h.transport.requests(matching: "/households/local/groups").count == groupsBefore + 1)
        await h.household.stop()
    }

    @Test func eqReadsAndWritesThroughUPnP() async throws {
        let h = Harness()
        _ = try await h.startAndDiscover(stereo)
        h.transport.respond(whenPathContains: "RenderingControl", sequence: [
            StubResponse(body: Fixtures.data("soap_GetBass.xml")),
            StubResponse(body: Data(SOAP.envelope(action: "GetTrebleResponse", arguments: [("CurrentTreble", "1")]).utf8)),
            StubResponse(body: Fixtures.data("soap_GetLoudness.xml")),
        ])
        let eq = try await h.household.eq(player: "RINCON_48A6B8194D2A01400")
        #expect(eq == EQSettings(bass: -3, treble: 1, loudness: true, subGain: nil))
        try await h.household.setEQ(EQSettings(bass: 0, treble: 0, loudness: false, subGain: nil), player: "RINCON_48A6B8194D2A01400")
        #expect(h.transport.requests.filter { $0.url.host() == "192.168.1.28" && $0.url.port == 1400 }.count >= 6)
        await #expect(throws: HouseholdError.unknownPlayer) { _ = try await h.household.eq(player: "nope") }
        await h.household.stop()
    }

    @Test func topologyEventOpensAndClosesSockets() async throws {
        let h = Harness()
        _ = try await h.startAndDiscover(stereo)
        try await waitUntil { h.transport.socketCount == 4 }
        let stereoSocket = try #require(h.transport.socket(forHost: "192.168.1.105"))
        let lines = Fixtures.lines("events.jsonl")
        let groupsEvent = try #require(lines.first { $0.contains(#""type":"groups""#) })
        // Same 4 players, so no new sockets; Flyttbar keeps its coordinator role.
        stereoSocket.push(groupsEvent)
        try await waitUntil { await h.household.current.groups.map(\.name) == ["Elsas Sovrum", "Flyttbar + 1", "Sovrum"] }
        #expect(h.transport.socketCount == 4)

        h.discovery.emit(.lost(playerID: "RINCON_48A6B8194D2A01400"))
        try await waitUntil { await h.household.current.player("RINCON_48A6B8194D2A01400") == nil }
        #expect(await h.household.current.groups.map(\.name) == ["Elsas Sovrum", "Flyttbar + 1"])
        await h.household.stop()
    }

    @Test func noPlayersWithinTimeoutSetsStatus() async throws {
        let h = Harness(timeout: .milliseconds(30))
        let stream = await h.household.snapshots()
        await h.household.start()
        for await snapshot in stream where snapshot.status == .noPlayersFound { break }
        #expect(await h.household.current.status == .noPlayersFound)
        await h.household.stop()
    }

    @Test func invalidKeySetsUnauthorized() async throws {
        let h = Harness()
        h.transport.respond(whenPathContains: "/households/local/groups", status: 400, body: Fixtures.data("error_400_nokey.json"))
        let stream = await h.household.snapshots()
        await h.household.start()
        h.discovery.emit(.found(stereo))
        for await snapshot in stream where snapshot.status == .unauthorized { break }
        #expect(await h.household.current.status == .unauthorized)
        await h.household.stop()
    }

    @Test func permissionDeniedSetsStatus() async throws {
        let h = Harness()
        let stream = await h.household.snapshots()
        await h.household.start()
        h.discovery.emit(.permissionDenied)
        for await snapshot in stream where snapshot.status == .localNetworkDenied { break }
        #expect(await h.household.current.status == .localNetworkDenied)
        await h.household.stop()
    }

    // MARK: Fix round 1 regressions

    @Test func normalStartupNeverPublishesNoPlayersFound() async throws {
        let h = Harness()
        let stream = await h.household.snapshots()
        await h.household.start()
        h.discovery.emit(.found(stereo))
        var statuses: [HouseholdStatus] = []
        for await snapshot in stream {
            statuses.append(snapshot.status)
            if snapshot.status == .ready { break }
        }
        #expect(!statuses.contains(.noPlayersFound))
        await h.household.stop()
    }

    @Test func stopThenStartRecovers() async throws {
        let h = Harness()
        _ = try await h.startAndDiscover(stereo)
        try await waitUntil { h.transport.socketCount == 4 }
        await h.household.stop()
        await h.household.start()
        let stream = await h.household.snapshots()
        h.discovery.emit(.found(stereo))
        // A stale `.ready` status survives `stop()` by design (the snapshot itself isn't
        // reset), so the real proof of recovery is that startup machinery runs again: a
        // fresh `ensureSockets()` pass opens a brand-new set of sockets.
        try await waitUntil { h.transport.socketCount == 8 }
        for await snapshot in stream where snapshot.status == .ready { break }
        #expect(await h.household.current.status == .ready)
        await h.household.stop()
    }

    @Test func groupsEventWithChangedMembershipUpdatesGroupsAndResubscribes() async throws {
        let h = Harness()
        _ = try await h.startAndDiscover(stereo)
        try await waitUntil { h.transport.socketCount == 4 }
        let flyttbarSocket = try #require(h.transport.socket(forHost: "192.168.1.216"))
        try await waitUntil { flyttbarSocket.sentText.count == 4 }
        let newGid = "RINCON_542A1B73A25001400:99"
        // Same header shape as events.jsonl's "groups" frame; the body regroups the four
        // players: Sovrum joins Flyttbar's group (under the new id above), Stereo becomes
        // its own solo group, Elsas Sovrum is unchanged.
        let regroupedEvent = #"[{"namespace":"groups:1","householdId":"Sonos_DzRiRrFKF13cB3mZaqqRgpvjhm.jNjF8gvtxNWbfhVMFin7","locationId":"lc_b72df4e3ae75431c8fb7d892bf2c67db","name":"groups","type":"groups"},{"_objectType":"groups","groups":[{"_objectType":"group","id":"\#(newGid)","name":"Flyttbar + 1","coordinatorId":"RINCON_542A1B73A25001400","playbackState":"PLAYBACK_STATE_PLAYING","playerIds":["RINCON_542A1B73A25001400","RINCON_48A6B8194D2A01400"]},{"_objectType":"group","id":"RINCON_347E5C5091CE01400:1363582096","name":"Elsas Sovrum","coordinatorId":"RINCON_347E5C5091CE01400","playbackState":"PLAYBACK_STATE_IDLE","playerIds":["RINCON_347E5C5091CE01400"]},{"_objectType":"group","id":"RINCON_347E5C04E98101400:100","name":"Stereo","coordinatorId":"RINCON_347E5C04E98101400","playbackState":"PLAYBACK_STATE_IDLE","playerIds":["RINCON_347E5C04E98101400"]}],"players":[{"_objectType":"player","id":"RINCON_542A1B73A25001400","name":"Flyttbar","websocketUrl":"wss://192.168.1.216:1443/websocket/api"},{"_objectType":"player","id":"RINCON_347E5C5091CE01400","name":"Elsas Sovrum","websocketUrl":"wss://192.168.1.250:1443/websocket/api"},{"_objectType":"player","id":"RINCON_48A6B8194D2A01400","name":"Sovrum","websocketUrl":"wss://192.168.1.28:1443/websocket/api"},{"_objectType":"player","id":"RINCON_347E5C04E98101400","name":"Stereo","websocketUrl":"wss://192.168.1.105:1443/websocket/api"}],"partial":false}]"#
        flyttbarSocket.push(regroupedEvent)
        try await waitUntil { await h.household.current.groups.map(\.name) == ["Elsas Sovrum", "Flyttbar + 1", "Stereo"] }
        #expect(h.transport.socketCount == 4)
        try await waitUntil { flyttbarSocket.sentText.contains { $0.contains(newGid) && $0.contains(#""command":"subscribe""#) } }
        await h.household.stop()
    }

    // MARK: Fix round 2 (task 15b): initial-fetch retry and timeout semantics

    @Test func initialFetchFailureRetriesUntilItSucceeds() async throws {
        let h = Harness(backoff: Backoff(base: .milliseconds(5), max: .milliseconds(5), jitter: 0))
        h.transport.respond(whenPathContains: "/households/local/groups", sequence: [
            StubResponse(status: 500, body: Data()),
            StubResponse(status: 500, body: Data()),
            StubResponse(body: Fixtures.data("groups.json")),
        ])
        _ = try await h.startAndDiscover(stereo)
        #expect(h.transport.requests(matching: "/households/local/groups").count == 3)
        await h.household.stop()
    }

    @Test func initialFetchFailingUntilTheTimeoutSetsNoPlayersFound() async throws {
        let h = Harness(timeout: .milliseconds(150), backoff: Backoff(base: .milliseconds(5), max: .milliseconds(5), jitter: 0))
        h.transport.respond(whenPathContains: "/households/local/groups", status: 500, body: Data())
        let stream = await h.household.snapshots()
        await h.household.start()
        h.discovery.emit(.found(stereo))
        for await snapshot in stream where snapshot.status == .noPlayersFound { break }
        #expect(await h.household.current.status == .noPlayersFound)

        h.transport.respond(whenPathContains: "/households/local/groups", body: Fixtures.data("groups.json"))
        h.discovery.emit(.found(stereo))
        for await snapshot in stream where snapshot.status == .ready { break }
        #expect(await h.household.current.status == .ready)
        await h.household.stop()
    }
}
