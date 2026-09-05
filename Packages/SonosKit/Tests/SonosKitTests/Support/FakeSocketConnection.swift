import Foundation
import Synchronization
@testable import SonosKit

final class FakeSocketConnection: SocketConnection, Sendable {
    private let sentFrames = Mutex<[Data]>([])
    private let stream: AsyncThrowingStream<Data, any Error>
    private let continuation: AsyncThrowingStream<Data, any Error>.Continuation
    let url: URL

    private struct Gate {
        var blocked = false
        var waiters: [CheckedContinuation<Void, Never>] = []
    }
    /// Opt-in test hook: `blockSends()` suspends every `send()` call that starts before the
    /// matching `releaseSends()`. Connections behave normally (no gate) unless a test calls this.
    private let gate = Mutex(Gate())

    init(url: URL) {
        self.url = url
        (stream, continuation) = AsyncThrowingStream<Data, any Error>.makeStream()
    }

    var sent: [Data] { sentFrames.withLock { $0 } }
    var sentText: [String] { sent.map { String(decoding: $0, as: UTF8.self) } }

    /// Test hook: suspend the next `send()` call(s) until `releaseSends()` is called.
    func blockSends() {
        gate.withLock { $0.blocked = true }
    }

    /// Resume any `send()` calls suspended by `blockSends()`, and let future sends through.
    func releaseSends() {
        let waiters = gate.withLock { state -> [CheckedContinuation<Void, Never>] in
            state.blocked = false
            let waiters = state.waiters
            state.waiters = []
            return waiters
        }
        for waiter in waiters { waiter.resume() }
    }

    func send(_ data: Data) async throws {
        if gate.withLock({ $0.blocked }) {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let alreadyOpen = gate.withLock { state -> Bool in
                    guard state.blocked else { return true }
                    state.waiters.append(continuation)
                    return false
                }
                if alreadyOpen { continuation.resume() }
            }
        }
        sentFrames.withLock { $0.append(data) }
    }

    func messages() -> AsyncThrowingStream<Data, any Error> { stream }
    func ping() async throws {}
    func close() { continuation.finish() }

    /// Simulate the player sending a frame.
    func push(_ text: String) { continuation.yield(Data(text.utf8)) }
    /// Simulate the connection dying.
    func fail(_ error: any Error) { continuation.finish(throwing: error) }
}
