import Foundation

/// Exponential reconnect delay: base · 2^attempt, capped at `max`, plus up to `jitter` fraction extra.
public struct Backoff: Sendable {
    public var base: Duration
    public var max: Duration
    public var jitter: Double

    public init(base: Duration = .seconds(1), max: Duration = .seconds(60), jitter: Double = 0.25) {
        self.base = base
        self.max = max
        self.jitter = jitter
    }

    /// `random` must be in 0...1; pass `Double.random(in: 0...1)` in production.
    public func delay(attempt: Int, random: Double) -> Duration {
        let exponent = Swift.min(Swift.max(attempt, 0), 30)
        let raw = base * (1 << exponent)
        let capped = raw < max ? raw : max
        let jitterThousandths = Int((random * jitter * 1000).rounded())
        return capped + (capped * jitterThousandths) / 1000
    }
}
