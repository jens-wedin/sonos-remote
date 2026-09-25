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
        let octets = parts.compactMap { octet($0) }
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
    /// An IPv6 literal is returned bare: `URLComponents.host` keeps the brackets a URL wraps it
    /// in (`"[fe80::1]"`), which is not an address any of the policy checks would recognise.
    public static func speakerHost(from urlString: String, schemes: Set<String>) -> String? {
        guard let components = URLComponents(string: urlString),
              let scheme = components.scheme?.lowercased(), schemes.contains(scheme),
              let rawHost = components.host else { return nil }
        let host = unbracketed(rawHost)
        guard isLocalSpeakerAddress(host) else { return nil }
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

    /// The leaf certificate's common name. Sonos names each speaker's certificate after its MAC.
    public static func leafCommonName(of trust: SecTrust) -> String? {
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = chain.first else { return nil }
        var name: CFString?
        guard SecCertificateCopyCommonName(leaf, &name) == errSecSuccess else { return nil }
        return name as String?
    }

    /// Whether `commonName` is the MAC embedded in `playerID` (`RINCON_<12 hex MAC><port>`), which is
    /// how a speaker's certificate names it (`CN=347E5C04E981` for `RINCON_347E5C04E98101400`).
    public static func playerID(_ playerID: String, matchesCommonName commonName: String) -> Bool {
        let prefix = "RINCON_"
        guard playerID.hasPrefix(prefix) else { return false }
        let mac = playerID.dropFirst(prefix.count).prefix(12)
        return mac.count == 12 && mac.uppercased() == commonName.uppercased()
    }

    private static func isIPv4Literal(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { octet($0) != nil }
    }

    /// One IPv4 octet, digits only. `UInt8(_:)` accepts a sign — `UInt8("+10") == 10` — so parsing
    /// the raw text would read "+10.0.0.7" as private 10/8 even though it is not an address at all.
    private static func octet(_ text: Substring) -> UInt8? {
        guard !text.isEmpty, text.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return UInt8(text)
    }

    /// An IPv6 literal without the square brackets a URL wraps it in; anything else unchanged.
    private static func unbracketed(_ host: String) -> String {
        guard host.count > 2, host.hasPrefix("["), host.hasSuffix("]") else { return host }
        return String(host.dropFirst().dropLast())
    }
}

/// Hosts discovered on the LAN whose self-signed certificate we accept, pinned to the key seen on first contact.
/// Speakers reissue their certificates (they last about six months), so a changed key is re-pinned when the
/// new certificate still names the player discovery put at that address; any other changed key is rejected.
public final class TrustStore: Sendable {
    private struct State: Sendable {
        var hosts: Set<String> = []
        var pins: [String: Data] = [:]
        /// The player ID each host was allowed for, when known. Not persisted: discovery and
        /// topology re-establish it every launch before the first request goes out.
        var playerIDs: [String: String] = [:]
        /// Players whose last contact presented a key that was rejected, so the app can say so.
        var rejected: Set<String> = []
        var observers: [UUID: AsyncStream<Set<String>>.Continuation] = [:]

        /// Adds or removes the host's player from `rejected`; returns the observers to notify when the set changed.
        mutating func mark(host: String, rejected isRejected: Bool) -> [AsyncStream<Set<String>>.Continuation] {
            guard let playerID = playerIDs[host] else { return [] }
            let changed = isRejected ? rejected.insert(playerID).inserted : rejected.remove(playerID) != nil
            return changed ? Array(observers.values) : []
        }
    }

    private let logger = Logger(subsystem: "com.jenswedin.SonosRemote", category: "trust")
    private let state: Mutex<State>
    private let pinStore: (any TrustPinStore)?

    public init(pinStore: (any TrustPinStore)? = nil) {
        self.pinStore = pinStore
        state = Mutex(State(hosts: [], pins: pinStore?.load() ?? [:]))
    }

    /// Allows `host`; `playerID` records which speaker lives there so a reissued certificate can be re-pinned.
    public func allow(host: String, playerID: String? = nil) {
        guard TrustPolicy.isLocalSpeakerAddress(host) else { return }
        state.withLock {
            _ = $0.hosts.insert(host)
            if let playerID { $0.playerIDs[host] = playerID }
        }
    }

    /// Forget a host, its pin and its player; the next contact pins afresh.
    public func revoke(host: String) {
        let (pins, notify, rejected) = state.withLock { s in
            let notify = s.mark(host: host, rejected: false)
            s.hosts.remove(host)
            s.pins[host] = nil
            s.playerIDs[host] = nil
            return (s.pins, notify, s.rejected)
        }
        pinStore?.save(pins)
        for observer in notify { observer.yield(rejected) }
    }

    /// Player IDs whose certificate is currently rejected.
    public var currentRejectedPlayers: Set<String> { state.withLock { $0.rejected } }

    /// The rejected player IDs now, then every time the set changes.
    public func rejectedPlayers() -> AsyncStream<Set<String>> {
        let (stream, continuation) = AsyncStream<Set<String>>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        let current = state.withLock { s in
            s.observers[id] = continuation
            return s.rejected
        }
        continuation.yield(current)
        continuation.onTermination = { [weak self] _ in
            _ = self?.state.withLock { $0.observers.removeValue(forKey: id) }
        }
        return stream
    }

    /// Trust-on-first-use: an allowed host with no pin records `keyHash`; afterwards the key must match,
    /// unless the certificate's `commonName` names the player allowed at that host (a reissued certificate).
    public func decision(host: String, port: Int, keyHash: Data, commonName: String? = nil) -> TrustDecision {
        guard port == TrustPolicy.speakerPort, TrustPolicy.isLocalSpeakerAddress(host) else { return .reject }
        let (decision, pins, repinned, notify, rejected) = state.withLock { s in
            let (decision, pins, repinned) = Self.decide(&s, host: host, keyHash: keyHash, commonName: commonName)
            let notify = s.mark(host: host, rejected: decision == .reject)
            return (decision, pins, repinned, notify, s.rejected)
        }
        if let pins { pinStore?.save(pins) }
        for observer in notify { observer.yield(rejected) }
        if repinned {
            logger.notice("re-pinned \(host, privacy: .private(mask: .hash)): the speaker reissued its certificate")
        }
        if decision == .reject {
            logger.error("rejected certificate for \(host, privacy: .private(mask: .hash)) on port \(port): key does not match the pinned speaker")
        }
        return decision
    }

    private static func decide(_ s: inout State, host: String, keyHash: Data, commonName: String?) -> (TrustDecision, [String: Data]?, Bool) {
        guard s.hosts.contains(host) else { return (.reject, nil, false) }
        if let pinned = s.pins[host], pinned != keyHash {
            guard let playerID = s.playerIDs[host], let commonName,
                  TrustPolicy.playerID(playerID, matchesCommonName: commonName) else { return (.reject, nil, false) }
            s.pins[host] = keyHash
            return (.accept, s.pins, true)
        }
        if s.pins[host] != nil { return (.accept, nil, false) }
        s.pins[host] = keyHash
        return (.accept, s.pins, false)
    }

    /// Kept for callers that only need the allow-list (the websocket URL builder, tests).
    public func shouldTrust(host: String) -> Bool {
        TrustPolicy.isLocalSpeakerAddress(host) && state.withLock { $0.hosts.contains(host) }
    }
}
