import Testing
@testable import SonosKit

@Suite struct BackoffTests {
    @Test func doublesFromBaseAndCaps() {
        let backoff = Backoff(base: .seconds(1), max: .seconds(60), jitter: 0)
        #expect(backoff.delay(attempt: 0, random: 0) == .seconds(1))
        #expect(backoff.delay(attempt: 1, random: 0) == .seconds(2))
        #expect(backoff.delay(attempt: 5, random: 0) == .seconds(32))
        #expect(backoff.delay(attempt: 6, random: 0) == .seconds(60))
        #expect(backoff.delay(attempt: 40, random: 0) == .seconds(60))
    }

    @Test func jitterAddsUpToTheFraction() {
        let backoff = Backoff(base: .seconds(1), max: .seconds(60), jitter: 0.25)
        #expect(backoff.delay(attempt: 0, random: 0) == .seconds(1))
        #expect(backoff.delay(attempt: 0, random: 1) == .milliseconds(1250))
        #expect(backoff.delay(attempt: 2, random: 0.5) == .milliseconds(4500))
    }
}
