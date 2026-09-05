import Synchronization
import Testing
@testable import SonosKit

@Suite struct DiscoveryTests {
    @Test func parsesPlayerFromTXTRecord() {
        let txt = [
            "uuid": "RINCON_347E5C04E98101400",
            "hhid": "Sonos_DzRiRrFKF13cB3mZaqqRgpvjhm",
            "location": "http://192.168.1.105:1400/xml/device_description.xml",
            "sslport": "1443",
            "variant": "2",
        ]
        let player = BonjourDiscovery.player(fromTXT: txt)
        #expect(player == DiscoveredPlayer(id: "RINCON_347E5C04E98101400", address: "192.168.1.105", householdID: "Sonos_DzRiRrFKF13cB3mZaqqRgpvjhm"))
    }

    @Test func recordWithoutUUIDOrLocationIsIgnored() {
        #expect(BonjourDiscovery.player(fromTXT: ["location": "http://192.168.1.105:1400/x"]) == nil)
        #expect(BonjourDiscovery.player(fromTXT: ["uuid": "RINCON_1"]) == nil)
        #expect(BonjourDiscovery.player(fromTXT: ["uuid": "RINCON_1", "location": "not a url"]) == nil)
    }

    @Test func fakeDiscoveryDeliversEvents() async {
        let discovery = FakeDiscovery()
        var iterator = discovery.events().makeAsyncIterator()
        discovery.emit(.found(DiscoveredPlayer(id: "RINCON_1", address: "192.168.1.5", householdID: nil)))
        discovery.emit(.lost(playerID: "RINCON_1"))
        #expect(await iterator.next() == .found(DiscoveredPlayer(id: "RINCON_1", address: "192.168.1.5", householdID: nil)))
        #expect(await iterator.next() == .lost(playerID: "RINCON_1"))
    }

    @Test func stopEndsTheEventStream() async throws {
        let discovery = BonjourDiscovery()
        let stream = discovery.events()
        discovery.stop()

        let finished = Mutex(false)
        Task {
            var iterator = stream.makeAsyncIterator()
            while await iterator.next() != nil {}
            finished.withLock { $0 = true }
        }

        try await waitUntil { finished.withLock { $0 } }
    }

    @Test func secondEventsCallEndsTheFirstStream() async throws {
        let discovery = BonjourDiscovery()
        let firstStream = discovery.events()
        _ = discovery.events()

        let finished = Mutex(false)
        Task {
            var iterator = firstStream.makeAsyncIterator()
            while await iterator.next() != nil {}
            finished.withLock { $0 = true }
        }

        try await waitUntil { finished.withLock { $0 } }
        discovery.stop()
    }
}
