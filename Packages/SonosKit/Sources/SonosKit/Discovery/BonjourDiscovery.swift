import Foundation
import Network
import Synchronization

/// Browses `_sonos._tcp` with NWBrowser. Works inside the App Sandbox as long as Info.plist
/// lists the service in NSBonjourServices and has NSLocalNetworkUsageDescription.
public final class BonjourDiscovery: Discovering, @unchecked Sendable {
    public static let serviceType = "_sonos._tcp"
    private static let policyDenied: Int32 = -65570 // kDNSServiceErr_PolicyDenied

    private let browser = Mutex<NWBrowser?>(nil)

    public init() {}

    public static func player(fromTXT txt: [String: String]) -> DiscoveredPlayer? {
        guard let id = txt["uuid"], !id.isEmpty,
              let location = txt["location"],
              let host = URLComponents(string: location)?.host, !host.isEmpty else { return nil }
        return DiscoveredPlayer(id: id, address: host, householdID: txt["hhid"])
    }

    public func events() -> AsyncStream<DiscoveryEvent> {
        let (stream, continuation) = AsyncStream<DiscoveryEvent>.makeStream()
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: Self.serviceType, domain: nil), using: NWParameters())

        browser.stateUpdateHandler = { state in
            if case .waiting(let error) = state, case .dns(let code) = error, code == Self.policyDenied {
                continuation.yield(.permissionDenied)
            }
            if case .failed(let error) = state, case .dns(let code) = error, code == Self.policyDenied {
                continuation.yield(.permissionDenied)
            }
        }

        browser.browseResultsChangedHandler = { _, changes in
            for change in changes {
                switch change {
                case .added(let result):
                    if let player = Self.player(from: result) { continuation.yield(.found(player)) }
                case .changed(_, let result, let flags) where flags.contains(.metadataChanged):
                    if let player = Self.player(from: result) { continuation.yield(.found(player)) }
                case .removed(let result):
                    if let player = Self.player(from: result) { continuation.yield(.lost(playerID: player.id)) }
                default:
                    break
                }
            }
        }

        continuation.onTermination = { _ in browser.cancel() }
        self.browser.withLock { old in
            old?.cancel()
            old = browser
        }
        browser.start(queue: DispatchQueue(label: "sonoskit.bonjour"))
        return stream
    }

    public func stop() {
        browser.withLock { $0?.cancel(); $0 = nil }
    }

    private static func player(from result: NWBrowser.Result) -> DiscoveredPlayer? {
        guard case .bonjour(let record) = result.metadata else { return nil }
        return player(fromTXT: record.dictionary)
    }
}
