import Foundation
import Testing
@testable import SonosKit

@Suite struct PlayerSocketTests {
    let fastBackoff = Backoff(base: .milliseconds(1), max: .milliseconds(5), jitter: 0)

    @Test func connectsSubscribesAndDecodesEvents() async throws {
        let transport = FakeTransport()
        let socket = PlayerSocket(playerID: "P1", address: "192.168.1.216", transport: transport, backoff: fastBackoff)
        await socket.setSubscriptions([Subscription(namespace: "groupVolume:1", scope: .group("G1"))])
        await socket.start()
        var outputs = socket.outputs.makeAsyncIterator()

        #expect(await outputs.next() == .connected)
        let connection = try #require(transport.socket(forHost: "192.168.1.216"))
        #expect(connection.url.absoluteString == "wss://192.168.1.216:1443/websocket/api")
        #expect(connection.sentText.count == 1)
        #expect(connection.sentText[0].contains(#""command":"subscribe""#))
        #expect(connection.sentText[0].contains(#""namespace":"groupVolume:1""#))

        connection.push(#"[{"namespace":"groupVolume:1","type":"groupVolume","groupId":"G1"},{"volume":7,"muted":false,"fixed":false}]"#)
        #expect(await outputs.next() == .event(.groupVolume(groupID: "G1", volume: Volume(level: 7, muted: false, fixed: false))))

        await socket.stop()
    }

    @Test func reconnectsAfterTheConnectionDrops() async throws {
        let transport = FakeTransport()
        let socket = PlayerSocket(playerID: "P1", address: "192.168.1.216", transport: transport, backoff: fastBackoff)
        await socket.setSubscriptions([Subscription(namespace: "playback:1", scope: .group("G1"))])
        await socket.start()
        var outputs = socket.outputs.makeAsyncIterator()

        #expect(await outputs.next() == .connected)
        transport.sockets[0].fail(URLError(.networkConnectionLost))
        #expect(await outputs.next() == .disconnected)
        #expect(await outputs.next() == .connected)
        #expect(transport.socketCount == 2)
        #expect(transport.sockets[1].sentText.count == 1)

        await socket.stop()
    }

    @Test func changingSubscriptionsSendsUnsubscribeAndSubscribe() async throws {
        let transport = FakeTransport()
        let socket = PlayerSocket(playerID: "P1", address: "192.168.1.216", transport: transport, backoff: fastBackoff)
        let volume = Subscription(namespace: "playerVolume:1", scope: .player("P1"))
        let playback = Subscription(namespace: "playback:1", scope: .group("G1"))
        await socket.setSubscriptions([volume, playback])
        await socket.start()
        var outputs = socket.outputs.makeAsyncIterator()
        #expect(await outputs.next() == .connected)
        let connection = transport.sockets[0]
        #expect(connection.sentText.count == 2)

        await socket.setSubscriptions([volume])
        try await waitUntil { connection.sentText.count == 3 }
        #expect(connection.sentText[2].contains(#""command":"unsubscribe""#))
        #expect(connection.sentText[2].contains(#""groupId":"G1""#))

        await socket.setSubscriptions([volume, Subscription(namespace: "groupVolume:1", scope: .group("G2"))])
        try await waitUntil { connection.sentText.count == 4 }
        #expect(connection.sentText[3].contains(#""command":"subscribe""#))
        #expect(connection.sentText[3].contains(#""groupId":"G2""#))

        await socket.stop()
    }

    /// Regression test: a `setSubscriptions` call that lands while the initial post-connect
    /// subscribe sends are still in flight must not be lost or double-counted. Before the fix,
    /// `self.connection` was published before those sends completed, so a concurrent
    /// `setSubscriptions` could see a connection but a stale (usually empty) `active`, computing
    /// its diff against the wrong baseline; `run()` would then clobber `active` afterwards,
    /// silently dropping subscriptions that were never unsubscribed.
    @Test func setSubscriptionsDuringInitialConnectIsReconciledAfterConnecting() async throws {
        let transport = FakeTransport()
        let socket = PlayerSocket(playerID: "P1", address: "192.168.1.216", transport: transport, backoff: fastBackoff)
        let a = Subscription(namespace: "playerVolume:1", scope: .player("A"))
        let b = Subscription(namespace: "playerVolume:1", scope: .player("B"))
        let c = Subscription(namespace: "playerVolume:1", scope: .player("C"))
        await socket.setSubscriptions([a, b])
        transport.onSocketOpened { $0.blockSends() }

        await socket.start()
        var outputs = socket.outputs.makeAsyncIterator()

        try await waitUntil { transport.socketCount == 1 }
        let connection = transport.sockets[0]

        // The initial subscribe(A)/subscribe(B) sends are blocked, so `self.connection` has not
        // been published yet: this call can only update `desired`, not touch `active`.
        await socket.setSubscriptions([a, c])
        connection.releaseSends()

        #expect(await outputs.next() == .connected)
        #expect(connection.sentText.count == 4)
        let initialSends = connection.sentText[0...1]
        #expect(initialSends.contains { $0.contains(#""command":"subscribe""#) && $0.contains(#""playerId":"A""#) })
        #expect(initialSends.contains { $0.contains(#""command":"subscribe""#) && $0.contains(#""playerId":"B""#) })
        #expect(connection.sentText[2].contains(#""command":"unsubscribe""#))
        #expect(connection.sentText[2].contains(#""playerId":"B""#))
        #expect(connection.sentText[3].contains(#""command":"subscribe""#))
        #expect(connection.sentText[3].contains(#""playerId":"C""#))

        await socket.stop()
    }

    @Test func stopEndsTheOutputStream() async throws {
        let transport = FakeTransport()
        let socket = PlayerSocket(playerID: "P1", address: "192.168.1.216", transport: transport, backoff: fastBackoff)
        await socket.start()
        var outputs = socket.outputs.makeAsyncIterator()
        #expect(await outputs.next() == .connected)
        await socket.stop()
        var sawEnd = false
        while let output = await outputs.next() {
            if output == .disconnected { sawEnd = true }
        }
        #expect(sawEnd)
    }
}
