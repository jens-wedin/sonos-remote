import AppKit
import Foundation
import Testing
@testable import SonosRemote

/// Returns a fixed release or throws; counts calls so tests can prove the source was never asked.
actor FakeReleaseSource: ReleaseSource {
    private(set) var calls = 0
    private var result: Result<ReleaseInfo, Error>

    init(_ result: Result<ReleaseInfo, Error>) { self.result = result }

    func set(_ result: Result<ReleaseInfo, Error>) { self.result = result }

    func latest() async throws -> ReleaseInfo {
        calls += 1
        return try result.get()
    }
}

/// A clock the test moves by hand.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    init(_ start: Date = Date(timeIntervalSince1970: 1_700_000_000)) { current = start }
    var now: Date { lock.withLock { current } }
    func advance(by seconds: TimeInterval) { lock.withLock { current = current.addingTimeInterval(seconds) } }
}

@MainActor
@Suite struct UpdateCheckerTests {
    func release(_ version: String) -> ReleaseInfo {
        ReleaseInfo(version: version, tag: "v\(version)", notesURL: URL(string: "https://example.com/releases/tag/v\(version)")!)
    }

    /// A checker over a private UserDefaults suite and a private pasteboard; the timer's first tick is an hour away so it never fires in a test.
    func makeChecker(
        source: FakeReleaseSource,
        current: String = "0.2.1",
        clock: TestClock = TestClock()
    ) -> (UpdateChecker, UserDefaults, NSPasteboard) {
        let name = "UpdateCheckerTests-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(name))
        let checker = UpdateChecker(
            source: source,
            currentVersion: current,
            defaults: defaults,
            pasteboard: pasteboard,
            now: { clock.now },
            initialDelay: .seconds(3600),
            interval: .seconds(86_400)
        )
        return (checker, defaults, pasteboard)
    }

    @Test func newerReleaseBecomesAvailable() async {
        let source = FakeReleaseSource(.success(release("0.2.2")))
        let (checker, defaults, _) = makeChecker(source: source)
        await checker.check()
        #expect(checker.available == release("0.2.2"))
        #expect(checker.latestKnown == release("0.2.2"))
        #expect(defaults.object(forKey: UpdateChecker.lastCheckKey) is Date)
    }

    @Test func sameOrOlderReleaseIsNotAvailable() async {
        let same = FakeReleaseSource(.success(release("0.2.1")))
        let (checker1, _, _) = makeChecker(source: same)
        await checker1.check()
        #expect(checker1.available == nil)
        #expect(checker1.latestKnown == nil)

        let older = FakeReleaseSource(.success(release("0.1.0")))
        let (checker2, _, _) = makeChecker(source: older)
        await checker2.check()
        #expect(checker2.available == nil)
    }

    @Test func dismissHidesTheVersionUntilANewerOneAppears() async {
        let source = FakeReleaseSource(.success(release("0.2.2")))
        let (checker, defaults, _) = makeChecker(source: source)
        await checker.check()
        checker.dismiss()
        #expect(checker.available == nil)
        #expect(checker.latestKnown == release("0.2.2"))
        #expect(defaults.string(forKey: UpdateChecker.dismissedKey) == "0.2.2")

        await checker.check()
        #expect(checker.available == nil)

        await source.set(.success(release("0.2.3")))
        await checker.check()
        #expect(checker.available == release("0.2.3"))
        #expect(checker.latestKnown == release("0.2.3"))
    }

    @Test func enabledDefaultsToTrue() {
        let source = FakeReleaseSource(.success(release("0.2.2")))
        let (checker, _, _) = makeChecker(source: source)
        #expect(checker.isEnabled)
    }

    @Test func disabledNeverAsksTheSourceAndClearsState() async throws {
        let source = FakeReleaseSource(.success(release("0.2.2")))
        let (checker, defaults, _) = makeChecker(source: source)
        await checker.check()
        #expect(checker.available != nil)

        checker.isEnabled = false
        #expect(defaults.bool(forKey: UpdateChecker.enabledKey) == false)
        #expect(checker.available == nil)
        #expect(checker.latestKnown == nil)

        await checker.check()
        checker.checkIfDue()
        try await Task.sleep(for: .milliseconds(100))
        let calls = await source.calls
        #expect(calls == 1)
        #expect(checker.available == nil)
    }

    @Test func reEnablingChecksAtOnce() async throws {
        let source = FakeReleaseSource(.success(release("0.2.2")))
        let (checker, defaults, _) = makeChecker(source: source)
        checker.isEnabled = false
        checker.isEnabled = true
        #expect(defaults.bool(forKey: UpdateChecker.enabledKey) == true)
        try await waitUntil { checker.available != nil }
        let calls = await source.calls
        #expect(calls == 1)
    }

    @Test func checkIfDueSkipsWithinADayAndRunsAfter() async throws {
        let source = FakeReleaseSource(.success(release("0.2.2")))
        let clock = TestClock()
        let (checker, defaults, _) = makeChecker(source: source, clock: clock)
        defaults.set(clock.now.addingTimeInterval(-3600), forKey: UpdateChecker.lastCheckKey)

        checker.checkIfDue()
        try await Task.sleep(for: .milliseconds(100))
        let callsAfterSkip = await source.calls
        #expect(callsAfterSkip == 0)

        clock.advance(by: 86_400)
        checker.checkIfDue()
        try await waitUntil { checker.available != nil }
        let callsAfterRun = await source.calls
        #expect(callsAfterRun == 1)
        #expect(defaults.object(forKey: UpdateChecker.lastCheckKey) as? Date == clock.now)
    }

    @Test func checkIfDueWithNoRecordedCheckLeavesItToTheLaunchTimer() async throws {
        let source = FakeReleaseSource(.success(release("0.2.2")))
        let (checker, _, _) = makeChecker(source: source)
        checker.checkIfDue()
        try await Task.sleep(for: .milliseconds(100))
        let calls = await source.calls
        #expect(calls == 0)
        #expect(checker.available == nil)
    }

    @Test func failureLeavesAvailableNilAndStillRecordsTheCheck() async {
        let source = FakeReleaseSource(.failure(ReleaseSourceError.http(503)))
        let (checker, defaults, _) = makeChecker(source: source)
        await checker.check()
        #expect(checker.available == nil)
        #expect(checker.latestKnown == nil)
        #expect(defaults.object(forKey: UpdateChecker.lastCheckKey) is Date)
    }

    @Test func aPreReleaseArrivesAsAnErrorAndIsIgnored() async {
        let source = FakeReleaseSource(.failure(ReleaseSourceError.notStable(tag: "v0.3.0-beta.1")))
        let (checker, _, _) = makeChecker(source: source)
        await checker.check()
        #expect(checker.available == nil)
        #expect(checker.latestKnown == nil)
    }

    @Test func catchingUpClearsLatestKnown() async {
        let source = FakeReleaseSource(.success(release("0.2.2")))
        let (checker, _, _) = makeChecker(source: source)
        await checker.check()
        #expect(checker.latestKnown == release("0.2.2"))

        // The user updated and relaunched: a checker for the new running version finds nothing newer.
        let (updated, _, _) = makeChecker(source: source, current: "0.2.2")
        await updated.check()
        #expect(updated.available == nil)
        #expect(updated.latestKnown == nil)
    }

    @Test func copyCommandPutsTheBrewLineOnThePasteboard() {
        let source = FakeReleaseSource(.success(release("0.2.2")))
        let (checker, _, pasteboard) = makeChecker(source: source)
        #expect(checker.brewCommand == "brew upgrade --cask remote-for-sonos")
        checker.copyCommand()
        #expect(pasteboard.string(forType: .string) == "brew upgrade --cask remote-for-sonos")
    }

    /// Polls `condition` every 20 ms for up to two seconds, then records a failure.
    private func waitUntil(_ condition: @MainActor () async -> Bool) async throws {
        for _ in 0..<100 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("condition not met within 2 s")
    }
}
