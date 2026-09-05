import Foundation
import Synchronization
@testable import SonosKit

final class FakeSocketConnection: SocketConnection, Sendable {
    private let sentFrames = Mutex<[Data]>([])
    private let stream: AsyncThrowingStream<Data, any Error>
    private let continuation: AsyncThrowingStream<Data, any Error>.Continuation
    let url: URL

    init(url: URL) {
        self.url = url
        (stream, continuation) = AsyncThrowingStream<Data, any Error>.makeStream()
    }

    var sent: [Data] { sentFrames.withLock { $0 } }
    var sentText: [String] { sent.map { String(decoding: $0, as: UTF8.self) } }

    func send(_ data: Data) async throws { sentFrames.withLock { $0.append(data) } }
    func messages() -> AsyncThrowingStream<Data, any Error> { stream }
    func ping() async throws {}
    func close() { continuation.finish() }

    /// Simulate the player sending a frame.
    func push(_ text: String) { continuation.yield(Data(text.utf8)) }
    /// Simulate the connection dying.
    func fail(_ error: any Error) { continuation.finish(throwing: error) }
}
