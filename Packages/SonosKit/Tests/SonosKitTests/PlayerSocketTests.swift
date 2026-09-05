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
