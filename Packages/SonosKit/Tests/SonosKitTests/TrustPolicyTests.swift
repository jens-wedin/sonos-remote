import Foundation
import Testing
@testable import SonosKit

@Suite struct TrustPolicyTests {
    let keyA = Data(repeating: 0xA1, count: 32)
    let keyB = Data(repeating: 0xB2, count: 32)

    @Test func privateRangesAreRecognised() {
        #expect(TrustPolicy.isPrivateIPv4("192.168.1.105"))
        #expect(TrustPolicy.isPrivateIPv4("10.0.0.7"))
        #expect(TrustPolicy.isPrivateIPv4("172.16.0.1"))
        #expect(TrustPolicy.isPrivateIPv4("172.31.255.254"))
        #expect(!TrustPolicy.isPrivateIPv4("172.32.0.1"))
        #expect(!TrustPolicy.isPrivateIPv4("8.8.8.8"))
        #expect(!TrustPolicy.isPrivateIPv4("sonos.com"))
        #expect(!TrustPolicy.isPrivateIPv4("192.168.1"))
        #expect(!TrustPolicy.isPrivateIPv4("192.168.1.300"))
    }

    @Test func storeTrustsOnlyAllowedPrivateHosts() {
        let store = TrustStore()
        #expect(!store.shouldTrust(host: "192.168.1.105"))
        store.allow(host: "192.168.1.105")
        store.allow(host: "8.8.8.8")
        #expect(store.shouldTrust(host: "192.168.1.105"))
        #expect(!store.shouldTrust(host: "8.8.8.8"))
        #expect(!store.shouldTrust(host: "192.168.1.28"))
    }

    @Test func localSpeakerAddresses() {
        #expect(TrustPolicy.isLocalSpeakerAddress("192.168.1.10"))
        #expect(TrustPolicy.isLocalSpeakerAddress("10.0.0.7"))
        #expect(TrustPolicy.isLocalSpeakerAddress("172.16.4.4"))
        #expect(TrustPolicy.isLocalSpeakerAddress("169.254.10.1"))
        #expect(TrustPolicy.isLocalSpeakerAddress("fe80::1"))
        #expect(!TrustPolicy.isLocalSpeakerAddress("8.8.8.8"))
        #expect(!TrustPolicy.isLocalSpeakerAddress("sonos.example.com"))
        #expect(!TrustPolicy.isLocalSpeakerAddress("172.32.0.1"))
        #expect(!TrustPolicy.isLocalSpeakerAddress(""))
        #expect(!TrustPolicy.isLocalSpeakerAddress("+10.0.0.7"))
        #expect(!TrustPolicy.isLocalSpeakerAddress("10.0.0.+7"))
        #expect(!TrustPolicy.isLocalSpeakerAddress("fdsonos.local"))
        #expect(!TrustPolicy.isLocalSpeakerAddress("169.254.example.com"))
    }

    @Test func speakerHostRequiresAllowedSchemeAndLocalLiteral() {
        #expect(TrustPolicy.speakerHost(from: "http://192.168.1.10:1400/xml/device_description.xml", schemes: ["http", "https"]) == "192.168.1.10")
        #expect(TrustPolicy.speakerHost(from: "wss://192.168.1.10:1443/websocket/api", schemes: ["wss"]) == "192.168.1.10")
        #expect(TrustPolicy.speakerHost(from: "https://attacker.example/x", schemes: ["http", "https"]) == nil)
        #expect(TrustPolicy.speakerHost(from: "http://93.184.216.34/x", schemes: ["http", "https"]) == nil)
        #expect(TrustPolicy.speakerHost(from: "file:///etc/hosts", schemes: ["http", "https"]) == nil)
        #expect(TrustPolicy.speakerHost(from: "ws://192.168.1.10/", schemes: ["wss"]) == nil)
        #expect(TrustPolicy.speakerHost(from: "wss://[fe80::1]:1443/websocket/api", schemes: ["wss"]) == "fe80::1")
        #expect(TrustPolicy.speakerHost(from: "http://[2001:db8::1]:1400/x", schemes: ["http"]) == nil)
    }

    @Test func firstContactPinsAndLaterContactsMustMatch() {
        let store = TrustStore()
        #expect(store.decision(host: "192.168.1.10", port: 1443, keyHash: keyA) == .reject, "not allowed yet")
        store.allow(host: "192.168.1.10")
        #expect(store.decision(host: "192.168.1.10", port: 1443, keyHash: keyA) == .accept, "first contact records the pin")
        #expect(store.decision(host: "192.168.1.10", port: 1443, keyHash: keyA) == .accept)
        #expect(store.decision(host: "192.168.1.10", port: 1443, keyHash: keyB) == .reject, "a different key is an impostor")
        #expect(store.decision(host: "192.168.1.10", port: 8443, keyHash: keyA) == .reject, "only the speaker port")
        #expect(store.decision(host: "8.8.8.8", port: 1443, keyHash: keyA) == .reject)
    }

    @Test func revokeForgetsHostAndPin() {
        let store = TrustStore()
        store.allow(host: "192.168.1.10")
        _ = store.decision(host: "192.168.1.10", port: 1443, keyHash: keyA)
        store.revoke(host: "192.168.1.10")
        #expect(store.decision(host: "192.168.1.10", port: 1443, keyHash: keyB) == .reject)
        store.allow(host: "192.168.1.10")
        #expect(store.decision(host: "192.168.1.10", port: 1443, keyHash: keyB) == .accept, "after revoke the next contact pins afresh")
    }

    @Test func commonNameMatchesTheMacInsideTheRinconID() {
        #expect(TrustPolicy.playerID("RINCON_347E5C04E98101400", matchesCommonName: "347E5C04E981"))
        #expect(TrustPolicy.playerID("RINCON_347E5C04E98101400", matchesCommonName: "347e5c04e981"), "hex case is not significant")
        #expect(!TrustPolicy.playerID("RINCON_347E5C04E98101400", matchesCommonName: "48A6B8194D2A"), "another speaker's certificate")
        #expect(!TrustPolicy.playerID("RINCON_347E5C04E98101400", matchesCommonName: "347E5C04E98"), "a prefix is not a match")
        #expect(!TrustPolicy.playerID("RINCON_347E5C04E98101400", matchesCommonName: ""))
        #expect(!TrustPolicy.playerID("347E5C04E98101400", matchesCommonName: "347E5C04E981"), "not a RINCON id")
    }

    @Test func aRotatedCertificateForTheSameSpeakerIsRepinned() {
        let pins = MemoryPins()
        let store = TrustStore(pinStore: pins)
        store.allow(host: "192.168.1.10", playerID: "RINCON_347E5C04E98101400")
        _ = store.decision(host: "192.168.1.10", port: 1443, keyHash: keyA, commonName: "347E5C04E981")
        #expect(store.decision(host: "192.168.1.10", port: 1443, keyHash: keyB, commonName: "347E5C04E981") == .accept,
                "the speaker reissued its certificate; its CN still names it")
        #expect(pins.saved["192.168.1.10"] == keyB, "the new key replaced the old pin")
    }

    @Test func aChangedKeyNamingAnotherSpeakerIsStillRejected() {
        let store = TrustStore()
        store.allow(host: "192.168.1.10", playerID: "RINCON_347E5C04E98101400")
        _ = store.decision(host: "192.168.1.10", port: 1443, keyHash: keyA, commonName: "347E5C04E981")
        #expect(store.decision(host: "192.168.1.10", port: 1443, keyHash: keyB, commonName: "48A6B8194D2A") == .reject)
        #expect(store.decision(host: "192.168.1.10", port: 1443, keyHash: keyB, commonName: nil) == .reject)
        #expect(store.decision(host: "192.168.1.10", port: 1443, keyHash: keyA, commonName: "347E5C04E981") == .accept,
                "a rejected impostor leaves the original pin in place")
    }

    @Test func aChangedKeyOnAHostWithNoKnownPlayerIsStillRejected() {
        let store = TrustStore()
        store.allow(host: "192.168.1.10")
        _ = store.decision(host: "192.168.1.10", port: 1443, keyHash: keyA, commonName: "347E5C04E981")
        #expect(store.decision(host: "192.168.1.10", port: 1443, keyHash: keyB, commonName: "347E5C04E981") == .reject)
    }

    @Test func revokeForgetsThePlayerIdentity() {
        let store = TrustStore()
        store.allow(host: "192.168.1.10", playerID: "RINCON_347E5C04E98101400")
        _ = store.decision(host: "192.168.1.10", port: 1443, keyHash: keyA, commonName: "347E5C04E981")
        store.revoke(host: "192.168.1.10")
        store.allow(host: "192.168.1.10")
        _ = store.decision(host: "192.168.1.10", port: 1443, keyHash: keyB, commonName: "48A6B8194D2A")
        #expect(store.decision(host: "192.168.1.10", port: 1443, keyHash: keyA, commonName: "347E5C04E981") == .reject,
                "the address now belongs to an unnamed host; the old player's identity must not re-pin it")
    }

    @Test func pinsPersistThroughTheStore() {
        let pins = MemoryPins()
        let first = TrustStore(pinStore: pins)
        first.allow(host: "192.168.1.10")
        _ = first.decision(host: "192.168.1.10", port: 1443, keyHash: keyA)
        #expect(pins.saved["192.168.1.10"] == keyA)
        let second = TrustStore(pinStore: pins)
        second.allow(host: "192.168.1.10")
        #expect(second.decision(host: "192.168.1.10", port: 1443, keyHash: keyB) == .reject, "the persisted pin survives a relaunch")
        #expect(second.decision(host: "192.168.1.10", port: 1443, keyHash: keyA) == .accept)
    }
}

private final class MemoryPins: TrustPinStore, @unchecked Sendable {
    var saved: [String: Data] = [:]
    func load() -> [String: Data] { saved }
    func save(_ pins: [String: Data]) { saved = pins }
}
