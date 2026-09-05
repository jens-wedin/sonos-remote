import Foundation
import Synchronization

public enum TrustPolicy {
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
}

/// Hosts discovered on the LAN whose self-signed certificate we accept.
public final class TrustStore: Sendable {
    private let hosts = Mutex<Set<String>>([])

    public init() {}

    public func allow(host: String) {
        _ = hosts.withLock { $0.insert(host) }
    }

    public func shouldTrust(host: String) -> Bool {
        TrustPolicy.isPrivateIPv4(host) && hosts.withLock { $0.contains(host) }
    }
}
