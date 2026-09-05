import Foundation
@testable import SonosKit

final class FakeDiscovery: Discovering, Sendable {
    private let stream: AsyncStream<DiscoveryEvent>
    private let continuation: AsyncStream<DiscoveryEvent>.Continuation

    init() {
        (stream, continuation) = AsyncStream<DiscoveryEvent>.makeStream()
    }

    func events() -> AsyncStream<DiscoveryEvent> { stream }
    func stop() { continuation.finish() }
    func emit(_ event: DiscoveryEvent) { continuation.yield(event) }
}
