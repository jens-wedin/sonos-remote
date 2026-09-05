import Foundation
import Synchronization
@testable import SonosKit

/// Supports `Household`'s actual usage pattern: `events()` once per `start()`, `stop()` once
/// per `stop()`, never overlapping (both are serialized actor methods). A stream/continuation
/// pair is always live — from `init()`, and again immediately after `stop()` swaps in a fresh
/// one — so `emit()` never races `events()`: it always lands on whichever pair is current,
/// and `events()` just hands back whatever stream is current whenever it happens to run,
/// buffering anything emitted before a consumer starts iterating.
final class FakeDiscovery: Discovering, Sendable {
    private struct Pair {
        var stream: AsyncStream<DiscoveryEvent>
        var continuation: AsyncStream<DiscoveryEvent>.Continuation
    }

    private static func makePair() -> Pair {
        let (stream, continuation) = AsyncStream<DiscoveryEvent>.makeStream()
        return Pair(stream: stream, continuation: continuation)
    }

    private let state: Mutex<Pair>

    init() {
        state = Mutex(Self.makePair())
    }

    func events() -> AsyncStream<DiscoveryEvent> {
        state.withLock { $0.stream }
    }

    /// Ends the current stream and immediately swaps in a fresh pair, so a later `events()`
    /// call (i.e. `start()` again) works without racing whichever task calls it.
    func stop() {
        let old = state.withLock { pair -> AsyncStream<DiscoveryEvent>.Continuation in
            let old = pair.continuation
            pair = Self.makePair()
            return old
        }
        old.finish()
    }

    func emit(_ event: DiscoveryEvent) {
        state.withLock { $0.continuation }.yield(event)
    }
}
