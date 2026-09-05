import Foundation

/// Throttles slider sends to one per `minimumInterval` and suppresses incoming volume events
/// for `suppressIncomingFor` after a send so the thumb does not jump back under the cursor.
struct VolumeCommandGate {
    var minimumInterval: TimeInterval
    var suppressIncomingFor: TimeInterval
    private(set) var lastSent: Date?
    private(set) var pending: Int?

    init(minimumInterval: TimeInterval = 0.1, suppressIncomingFor: TimeInterval = 0.5) {
        self.minimumInterval = minimumInterval
        self.suppressIncomingFor = suppressIncomingFor
    }

    var hasPending: Bool { pending != nil }

    /// Returns the value to send now, or nil if it was queued.
    mutating func userChanged(to value: Int, at now: Date) -> Int? {
        if let lastSent, now.timeIntervalSince(lastSent) < minimumInterval {
            pending = value
            return nil
        }
        lastSent = now
        pending = nil
        return value
    }

    /// Returns a queued value once the interval has passed, else nil.
    mutating func flush(at now: Date) -> Int? {
        guard let value = pending else { return nil }
        if let lastSent, now.timeIntervalSince(lastSent) < minimumInterval { return nil }
        lastSent = now
        pending = nil
        return value
    }

    func shouldAcceptIncoming(at now: Date) -> Bool {
        guard let lastSent else { return true }
        return now.timeIntervalSince(lastSent) >= suppressIncomingFor
    }
}
