import Foundation

struct WaitTimeout: Error {}

/// Polls `condition` every 10 ms until it is true or `timeout` elapses.
func waitUntil(timeout: Duration = .seconds(2), _ condition: @Sendable () async -> Bool) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while clock.now < deadline {
        if await condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    throw WaitTimeout()
}
