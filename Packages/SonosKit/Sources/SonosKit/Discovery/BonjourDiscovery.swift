import Foundation
import Network
import Synchronization

/// Browses `_sonos._tcp` with NWBrowser. Works inside the App Sandbox as long as Info.plist
/// lists the service in NSBonjourServices and has NSLocalNetworkUsageDescription.
public final class BonjourDiscovery: Discovering, @unchecked Sendable {
    public static let serviceType = "_sonos._tcp"
    private static let policyDenied: Int32 = -65570 // kDNSServiceErr_PolicyDenied

    /// A browser and the continuation that feeds its stream, kept together so `stop()` and a
    /// replacing `events()` call can always finish the continuation that goes with the browser
    /// they're cancelling.
    private struct Session {
        var browser: NWBrowser
        var continuation: AsyncStream<DiscoveryEvent>.Continuation
    }

    private let session = Mutex<Session?>(nil)

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
        // Latches .permissionDenied to a single yield per browser/stream: NWBrowser retries
        // periodically while .waiting, which would otherwise re-report the same denial.
        let permissionDeniedSent = Mutex(false)

        browser.stateUpdateHandler = { state in
            switch state {
            case .waiting(let error), .failed(let error):
                guard case .dns(let code) = error, code == Self.policyDenied else { return }
                let alreadySent = permissionDeniedSent.withLock { sent -> Bool in
                    defer { sent = true }
                    return sent
                }
                if !alreadySent { continuation.yield(.permissionDenied) }
            case .cancelled:
                // Ensures the stream ends even when cancellation is driven from outside
                // events()/stop() (e.g. the continuation's own onTermination). Finishing an
                // already-finished continuation is a no-op.
                continuation.finish()
            default:
                break
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
        session.withLock { current in
            // Replacing a still-open session: finish its stream immediately rather than
            // waiting on the async .cancelled callback from the browser we're tearing down.
            current?.continuation.finish()
            current?.browser.cancel()
            current = Session(browser: browser, continuation: continuation)
        }
        browser.start(queue: DispatchQueue(label: "sonoskit.bonjour"))
        return stream
    }

    public func stop() {
        session.withLock { current in
            current?.browser.cancel()
            current?.continuation.finish()
            current = nil
        }
    }

    private static func player(from result: NWBrowser.Result) -> DiscoveredPlayer? {
        guard case .bonjour(let record) = result.metadata else { return nil }
        return player(fromTXT: record.dictionary)
    }
}
