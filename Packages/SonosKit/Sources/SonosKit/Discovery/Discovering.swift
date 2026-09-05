import Foundation

public struct DiscoveredPlayer: Hashable, Sendable {
    public var id: String
    public var address: String
    public var householdID: String?

    public init(id: String, address: String, householdID: String?) {
        self.id = id
        self.address = address
        self.householdID = householdID
    }
}

public enum DiscoveryEvent: Hashable, Sendable {
    case found(DiscoveredPlayer)
    case lost(playerID: String)
    /// macOS Local Network permission was denied for this app.
    case permissionDenied
}

public protocol Discovering: Sendable {
    /// Starts browsing on first call. Ends when `stop()` is called.
    func events() -> AsyncStream<DiscoveryEvent>
    func stop()
}
