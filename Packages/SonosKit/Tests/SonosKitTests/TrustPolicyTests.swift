import Testing
@testable import SonosKit

@Suite struct TrustPolicyTests {
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
}
