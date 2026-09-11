import CryptoKit
import Foundation
import os
import Security
import Synchronization

public enum TrustDecision: Sendable, Equatable {
    case accept
    case reject
}

/// Where pins live between launches. The app persists them in UserDefaults; tests keep them in memory.
public protocol TrustPinStore: Sendable {
    func load() -> [String: Data]
    func save(_ pins: [String: Data])
}

public enum TrustPolicy {
    /// The only port the local Control API and websocket use.
    public static let speakerPort = 1443

    /// 10/8, 172.16/12, 192.168/16. Hostnames and public addresses are never private.
    public static func isPrivateIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        let octets = parts.compactMap { UInt8($0) }
        guard octets.count == 4 else { return false }
        switch (octets[0], octets[1]) {
        case (10, _): return true
        case (172, 16...31): return true
        case (192, 168): return true
        default: return false
        }
    }

    /// Private IPv4, IPv4 link-local (169.254/16), or IPv6 link-local / unique-local literals.
    /// Sonos always publishes IP literals; a DNS name is never a speaker.
    public static func isLocalSpeakerAddress(_ host: String) -> Bool {
        if isPrivateIPv4(host) { return true }
        if host.hasPrefix("169.254.") { return isIPv4Literal(host) }
        let lower = host.lowercased()
        if lower.contains(":") {
            return lower.hasPrefix("fe80:") || lower.hasPrefix("fc") || lower.hasPrefix("fd")
        }
        return false
    }

    /// The host of `urlString` when its scheme is allowed and the host is a local speaker literal.
    public static func speakerHost(from urlString: String, schemes: Set<String>) -> String? {
        guard let components = URLComponents(string: urlString),
              let scheme = components.scheme?.lowercased(), schemes.contains(scheme),
              let host = components.host, isLocalSpeakerAddress(host) else { return nil }
        return host
    }

    /// SHA-256 of the leaf certificate's public key (SPKI bytes), or nil when the chain is unreadable.
    public static func leafKeyHash(of trust: SecTrust) -> Data? {
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = chain.first,
              let key = SecCertificateCopyKey(leaf),
              let bytes = SecKeyCopyExternalRepresentation(key, nil) as Data? else { return nil }
        return Data(SHA256.hash(data: bytes))
    }

    private static func isIPv4Literal(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { UInt8($0) != nil }
    }
}

/// Hosts discovered on the LAN whose self-signed certificate we accept, pinned to the key seen on first contact.
public final class TrustStore: Sendable {
    private struct State: Sendable {
        var hosts: Set<String> = []
        var pins: [String: Data] = [:]
    }

    private let logger = Logger(subsystem: "com.jenswedin.SonosRemote", category: "trust")
    private let state: Mutex<State>
    private let pinStore: (any TrustPinStore)?

    public init(pinStore: (any TrustPinStore)? = nil) {
        self.pinStore = pinStore
        state = Mutex(State(hosts: [], pins: pinStore?.load() ?? [:]))
    }

    public func allow(host: String) {
        guard TrustPolicy.isLocalSpeakerAddress(host) else { return }
        state.withLock { _ = $0.hosts.insert(host) }
    }

    /// Forget a host and its pin; the next contact pins afresh.
    public func revoke(host: String) {
        let pins = state.withLock { s -> [String: Data] in
            s.hosts.remove(host)
            s.pins[host] = nil
            return s.pins
        }
        pinStore?.save(pins)
    }

    /// Trust-on-first-use: an allowed host with no pin records `keyHash`; afterwards the key must match.
    public func decision(host: String, port: Int, keyHash: Data) -> TrustDecision {
        guard port == TrustPolicy.speakerPort, TrustPolicy.isLocalSpeakerAddress(host) else { return .reject }
        let (decision, pins) = state.withLock { s -> (TrustDecision, [String: Data]?) in
            guard s.hosts.contains(host) else { return (.reject, nil) }
            if let pinned = s.pins[host] {
                return (pinned == keyHash ? .accept : .reject, nil)
            }
            s.pins[host] = keyHash
            return (.accept, s.pins)
        }
        if let pins { pinStore?.save(pins) }
        if decision == .reject {
            logger.error("rejected certificate for \(host, privacy: .private(mask: .hash)) on port \(port): key does not match the pinned speaker")
        }
        return decision
    }

    /// Kept for callers that only need the allow-list (the websocket URL builder, tests).
    public func shouldTrust(host: String) -> Bool {
        TrustPolicy.isLocalSpeakerAddress(host) && state.withLock { $0.hosts.contains(host) }
    }
}
