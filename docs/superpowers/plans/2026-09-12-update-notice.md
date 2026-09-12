# Update Notice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tell the user inside the panel when a newer GitHub release of Remote for Sonos exists, with a copyable Homebrew command and a "What's new" link, checked once a day and switchable off in Settings.

**Architecture:** A new `UpdateChecker` (`@MainActor @Observable`) in the app target fetches `releases/latest` from the GitHub API through a `ReleaseSource` protocol, compares semantic versions with `CFBundleShortVersionString`, and exposes `available` / `latestKnown`. `MainScreen` renders an `UpdateCard` above the hero while `available` is set; `SettingsScreen` gains a "Check for updates" switch and shows the version in the SYSTEM card. The app creates the checker at launch and injects it with `.environment`; the panel triggers a check on open when the last one is a day old. SonosKit is untouched.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI, Foundation `URLSession`, `os.Logger`, `AppKit` `NSPasteboard`, Swift Testing (`@Suite`/`@Test`/`#expect`), XcodeGen.

**Spec:** `docs/superpowers/specs/2026-09-12-update-notice-design.md`

## Global Constraints

- Every build/test command needs `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` first.
- Run `xcodegen generate` after adding or removing any file under `SonosRemote/` or `SonosRemoteTests/` (the project file is generated and not committed).
- Test command for the app target (from the repo root, after `xcodegen generate`):
  `xcodebuild test -project SonosRemote.xcodeproj -scheme SonosRemote -destination 'platform=macOS' -derivedDataPath .build/xcode 2>&1 | tail -5` — expect `** TEST SUCCEEDED **`. To run one suite add `-only-testing:SonosRemoteTests/<SuiteName>`. If the first run after a fresh signed build hangs for minutes and fails with "the test runner hung before establishing connection", rerun the same command once (`knowledge/ERRORS.md`, 2026-09-05).
- Never commit `SonosRemote.xcodeproj`, `.build/`, `.superpowers/`, or `knowledge/design/` (untracked, owner's decision pending).
- Swift 6 strict concurrency: every type crossing an actor boundary is `Sendable`; the checker is `@MainActor`; the release source protocol is `Sendable`.
- Endpoint: `GET https://api.github.com/repos/jens-wedin/sonos-remote/releases/latest`; headers `Accept: application/vnd.github+json`, `User-Agent: RemoteForSonos/<version>`; request timeout 8 s.
- Timing: first check 30 s after launch, then every 24 h while running; on panel open when `lastUpdateCheck` is older than 24 h.
- Version rule: strict `major.minor.patch` compare; leading `v` stripped; missing minor/patch count as 0; anything after the numbers (pre-release suffix) makes the version unparsable and never newer.
- UserDefaults keys, verbatim: `updateCheckEnabled` (Bool, default true), `dismissedUpdateVersion` (String), `lastUpdateCheck` (Date).
- Copy, verbatim: card title `Update available — v<version>`; buttons "Copy Homebrew command" (swaps to "Copied" for 2 s) and "What's new"; Settings row "Check for updates" with caption "Asks github.com once a day"; Settings version second line "Update available: <version>"; Homebrew command `brew upgrade --cask remote-for-sonos`.
- Accessibility labels, verbatim: "Copy Homebrew upgrade command", "Show what's new in v<version>", "Dismiss update notice"; VoiceOver announcement "Update available, version <version>" once per version; every button `.focusable()`; text tokens from `Palette` (`Color.supporting`, never `.secondary`); user-supplied strings rendered with `Text(verbatim:)`.
- Failures are silent to the user: a `Logger(subsystem: "com.jenswedin.SonosRemote", category: "updates")` info line, `available` unchanged, `lastUpdateCheck` still updated.
- Commits: conventional commits; each commit message ends with the attribution lines the session's system reminder gives (`Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` and the `Claude-Session:` line).

---

## File structure

| File | Responsibility |
|---|---|
| `SonosRemote/App/SemanticVersion.swift` (create) | Pure version parsing and comparison. |
| `SonosRemote/App/ReleaseSource.swift` (create) | `ReleaseInfo`, `WireRelease`, `ReleaseSourceError`, `ReleaseSource` protocol, `GitHubReleaseSource`. |
| `SonosRemote/App/UpdateChecker.swift` (create) | The observable checker: policy, timer, defaults, pasteboard. |
| `SonosRemote/Views/Components/UpdateCard.swift` (create) | The card view. |
| `SonosRemote/Views/Main/MainScreen.swift` (modify) | Render the card. |
| `SonosRemote/Views/Settings/SettingsScreen.swift` (modify) | "Check for updates" row; version row second line. |
| `SonosRemote/App/SonosRemoteApp.swift` (modify) | Create, start, inject the checker. |
| `SonosRemote/Views/Shell/PanelShellView.swift` (modify) | `checkIfDue()` on panel open. |
| `SonosRemoteTests/SemanticVersionTests.swift`, `ReleaseDecodingTests.swift`, `UpdateCheckerTests.swift` (create) | Unit tests. |
| `SonosRemoteTests/Fixtures/github-release-latest.json` (exists, committed with this plan) | Real `releases/latest` response captured 2026-09-12 with `gh api repos/jens-wedin/sonos-remote/releases/latest`. |
| `README.md`, `changelog.md`, `knowledge/procedural/manual-test-checklist.md`, `knowledge/domain/github-releases-api.md`, `knowledge/INDEX.md` (modify/create) | Documentation. |

The spec puts all three model files in one `UpdateChecker.swift`; this plan splits them by responsibility (version maths, wire/network, policy) so each file stays small enough to review on its own. Behaviour is unchanged.

One ruling on a gap in the spec: the spec says `check()` ignores drafts and pre-releases, but `ReleaseSource.latest()` returns a `ReleaseInfo` that carries no draft flag. In this plan the `WireRelease` → `ReleaseInfo` conversion throws `ReleaseSourceError.notStable` for `draft || prerelease`, so a draft or pre-release reaches `check()` as an error and takes the silent-failure path the spec describes in §5. The "drafts and pre-releases ignored" test therefore lives in `ReleaseDecodingTests` (conversion throws) and `UpdateCheckerTests` (a throwing source leaves `available` nil).

A second ruling: `checkIfDue()` does nothing when no `lastUpdateCheck` has ever been recorded. The spec's launch timer runs an unconditional check 30 s after start, so a fresh install is covered without a second request when the panel is opened in those first 30 s; the "opened after days away" case the spec describes always has a recorded check.

A third: `copyCommand()` writes to an injectable `NSPasteboard` (default `.general`) so the unit test uses a private named pasteboard and never overwrites the owner's clipboard.

---

### Task 1: SemanticVersion

**Files:**
- Create: `SonosRemote/App/SemanticVersion.swift`
- Test: `SonosRemoteTests/SemanticVersionTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `enum SemanticVersion { static func parse(_ string: String) -> (major: Int, minor: Int, patch: Int)?; static func isNewer(_ candidate: String, than current: String) -> Bool }`.

- [ ] **Step 1: Write the failing tests**

Create `SonosRemoteTests/SemanticVersionTests.swift`:

```swift
import Testing
@testable import SonosRemote

@Suite struct SemanticVersionTests {
    @Test func parsesMajorMinorPatch() {
        let parsed = SemanticVersion.parse("0.2.1")
        #expect(parsed?.major == 0)
        #expect(parsed?.minor == 2)
        #expect(parsed?.patch == 1)
    }

    @Test func stripsLeadingVAndFillsMissingParts() {
        let parsed = SemanticVersion.parse("v1.0")
        #expect(parsed?.major == 1)
        #expect(parsed?.minor == 0)
        #expect(parsed?.patch == 0)
        #expect(SemanticVersion.parse("2")?.minor == 0)
    }

    @Test func rejectsPreReleaseSuffixAndGarbage() {
        #expect(SemanticVersion.parse("0.3.0-beta.1") == nil)
        #expect(SemanticVersion.parse("0.3.0rc1") == nil)
        #expect(SemanticVersion.parse("latest") == nil)
        #expect(SemanticVersion.parse("") == nil)
        #expect(SemanticVersion.parse("1.2.3.4") == nil)
        #expect(SemanticVersion.parse("1..3") == nil)
    }

    @Test func patchBumpIsNewer() {
        #expect(SemanticVersion.isNewer("0.2.2", than: "0.2.1"))
    }

    @Test func equalIsNotNewer() {
        #expect(!SemanticVersion.isNewer("0.2.1", than: "0.2.1"))
        #expect(!SemanticVersion.isNewer("v0.2.1", than: "0.2.1"))
    }

    @Test func olderIsNotNewer() {
        #expect(!SemanticVersion.isNewer("0.2.0", than: "0.2.1"))
        #expect(!SemanticVersion.isNewer("0.1.9", than: "0.2.0"))
    }

    @Test func minorBeatsPatchAndLeadingVIsIgnored() {
        #expect(SemanticVersion.isNewer("v0.3.0", than: "0.2.9"))
        #expect(SemanticVersion.isNewer("1.0", than: "0.9.9"))
    }

    @Test func preReleaseAndGarbageAreNeverNewer() {
        #expect(!SemanticVersion.isNewer("0.3.0-beta.1", than: "0.2.1"))
        #expect(!SemanticVersion.isNewer("latest", than: "0.2.1"))
        #expect(!SemanticVersion.isNewer("0.3.0", than: "dev"))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate
xcodebuild test -project SonosRemote.xcodeproj -scheme SonosRemote -destination 'platform=macOS' -derivedDataPath .build/xcode -only-testing:SonosRemoteTests/SemanticVersionTests 2>&1 | grep -E "error:|TEST (SUCCEEDED|FAILED)" | head
```
Expected: a compile error `cannot find 'SemanticVersion' in scope` and `** TEST FAILED **`.

- [ ] **Step 3: Write the implementation**

Create `SonosRemote/App/SemanticVersion.swift`:

```swift
import Foundation

/// Strict `major.minor.patch` handling for release tags (`v0.2.1`) and `CFBundleShortVersionString`.
/// Pre-release suffixes and anything else that is not digits and dots do not parse, so they can never be "newer".
enum SemanticVersion {
    /// "v1.2" → (1, 2, 0). Nil for an empty string, more than three parts, an empty part, or a non-digit character.
    static func parse(_ string: String) -> (major: Int, minor: Int, patch: Int)? {
        var text = Substring(string)
        if text.hasPrefix("v") { text = text.dropFirst() }
        guard !text.isEmpty else { return nil }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy(\.isNumber), let value = Int(part) else { return nil }
            numbers.append(value)
        }
        while numbers.count < 3 { numbers.append(0) }
        return (numbers[0], numbers[1], numbers[2])
    }

    /// True only when both sides parse and `candidate` is strictly greater.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard let a = parse(candidate), let b = parse(current) else { return false }
        return (a.major, a.minor, a.patch) > (b.major, b.minor, b.patch)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run the same command as Step 2. Expected: `** TEST SUCCEEDED **` and no `error:` lines.

- [ ] **Step 5: Commit**

```bash
git add SonosRemote/App/SemanticVersion.swift SonosRemoteTests/SemanticVersionTests.swift
git commit -m "feat(updates): strict semantic version compare for release tags"
```
(End the message with the attribution lines from the Global Constraints.)

---

### Task 2: ReleaseSource and the GitHub decoder

**Files:**
- Create: `SonosRemote/App/ReleaseSource.swift`
- Test: `SonosRemoteTests/ReleaseDecodingTests.swift`
- Uses: `SonosRemoteTests/Fixtures/github-release-latest.json` (already in the repo; XcodeGen adds every non-source file under `SonosRemoteTests/` to the test bundle's resources).

**Interfaces:**
- Consumes: `SemanticVersion.parse(_:)` (Task 1) to reject tags that are not `vX.Y.Z`.
- Produces:
  - `struct ReleaseInfo: Hashable, Sendable { let version: String; let tag: String; let notesURL: URL; init(version:tag:notesURL:); init(wire: WireRelease) throws }`
  - `struct WireRelease: Decodable, Sendable { let tagName: String; let htmlUrl: URL; let name: String?; let body: String?; let draft: Bool; let prerelease: Bool }`
  - `enum ReleaseSourceError: Error, Equatable { case http(Int); case notStable(tag: String); case unparsableTag(String) }`
  - `protocol ReleaseSource: Sendable { func latest() async throws -> ReleaseInfo }`
  - `struct GitHubReleaseSource: ReleaseSource { init(session: URLSession = .shared, userAgentVersion: String); static let endpoint: URL; func makeRequest() -> URLRequest }`

- [ ] **Step 1: Write the failing tests**

Create `SonosRemoteTests/ReleaseDecodingTests.swift`:

```swift
import Foundation
import Testing
@testable import SonosRemote

/// Anchor for `Bundle(for:)`; Swift Testing suites are structs, so a class is needed to find the test bundle.
private final class FixtureAnchor {}

@Suite struct ReleaseDecodingTests {
    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle(for: FixtureAnchor.self).url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }

    private func decode(_ data: Data) throws -> WireRelease {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(WireRelease.self, from: data)
    }

    @Test func decodesTheCapturedLatestRelease() throws {
        let wire = try decode(try fixture("github-release-latest"))
        #expect(wire.tagName == "v0.2.1")
        #expect(wire.htmlUrl.absoluteString == "https://github.com/jens-wedin/sonos-remote/releases/tag/v0.2.1")
        #expect(wire.name == "Remote for Sonos 0.2.1")
        #expect(wire.draft == false)
        #expect(wire.prerelease == false)
        #expect(wire.body?.isEmpty == false)
    }

    @Test func convertsToReleaseInfoWithoutTheV() throws {
        let info = try ReleaseInfo(wire: try decode(try fixture("github-release-latest")))
        #expect(info == ReleaseInfo(
            version: "0.2.1",
            tag: "v0.2.1",
            notesURL: URL(string: "https://github.com/jens-wedin/sonos-remote/releases/tag/v0.2.1")!
        ))
    }

    @Test func decodesMinimalJSONWithMissingOptionals() throws {
        let json = #"{"tag_name":"v0.3.0","html_url":"https://example.com/r/v0.3.0","draft":false,"prerelease":false}"#
        let info = try ReleaseInfo(wire: try decode(Data(json.utf8)))
        #expect(info.version == "0.3.0")
        #expect(info.tag == "v0.3.0")
    }

    @Test func preReleaseAndDraftThrowNotStable() throws {
        let pre = #"{"tag_name":"v0.3.0","html_url":"https://example.com/r","draft":false,"prerelease":true}"#
        let draft = #"{"tag_name":"v0.3.0","html_url":"https://example.com/r","draft":true,"prerelease":false}"#
        #expect(throws: ReleaseSourceError.notStable(tag: "v0.3.0")) {
            try ReleaseInfo(wire: try decode(Data(pre.utf8)))
        }
        #expect(throws: ReleaseSourceError.notStable(tag: "v0.3.0")) {
            try ReleaseInfo(wire: try decode(Data(draft.utf8)))
        }
    }

    @Test func unparsableTagThrows() throws {
        let json = #"{"tag_name":"nightly","html_url":"https://example.com/r","draft":false,"prerelease":false}"#
        #expect(throws: ReleaseSourceError.unparsableTag("nightly")) {
            try ReleaseInfo(wire: try decode(Data(json.utf8)))
        }
    }

    @Test func endpointAndHeadersAreFixed() {
        #expect(GitHubReleaseSource.endpoint.absoluteString == "https://api.github.com/repos/jens-wedin/sonos-remote/releases/latest")
        let request = GitHubReleaseSource(userAgentVersion: "0.2.1").makeRequest()
        #expect(request.url == GitHubReleaseSource.endpoint)
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "RemoteForSonos/0.2.1")
        #expect(request.timeoutInterval == 8)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate
xcodebuild test -project SonosRemote.xcodeproj -scheme SonosRemote -destination 'platform=macOS' -derivedDataPath .build/xcode -only-testing:SonosRemoteTests/ReleaseDecodingTests 2>&1 | grep -E "error:|TEST (SUCCEEDED|FAILED)" | head
```
Expected: compile errors (`cannot find 'WireRelease' in scope` etc.) and `** TEST FAILED **`.

- [ ] **Step 3: Write the implementation**

Create `SonosRemote/App/ReleaseSource.swift`:

```swift
import Foundation

/// The one release the checker cares about: version without the `v`, the tag, and the release page.
struct ReleaseInfo: Hashable, Sendable {
    let version: String
    let tag: String
    let notesURL: URL

    init(version: String, tag: String, notesURL: URL) {
        self.version = version
        self.tag = tag
        self.notesURL = notesURL
    }

    /// Throws `.notStable` for drafts and pre-releases and `.unparsableTag` when the tag is not `vX.Y.Z`.
    init(wire: WireRelease) throws {
        guard !wire.draft, !wire.prerelease else { throw ReleaseSourceError.notStable(tag: wire.tagName) }
        guard SemanticVersion.parse(wire.tagName) != nil else { throw ReleaseSourceError.unparsableTag(wire.tagName) }
        let version = wire.tagName.hasPrefix("v") ? String(wire.tagName.dropFirst()) : wire.tagName
        self.init(version: version, tag: wire.tagName, notesURL: wire.htmlUrl)
    }
}

/// The fields of GitHub's `releases/latest` response this app reads. Decode with `.convertFromSnakeCase`.
struct WireRelease: Decodable, Sendable {
    let tagName: String
    let htmlUrl: URL
    let name: String?
    let body: String?
    let draft: Bool
    let prerelease: Bool
}

enum ReleaseSourceError: Error, Equatable {
    case http(Int)
    case notStable(tag: String)
    case unparsableTag(String)
}

protocol ReleaseSource: Sendable {
    func latest() async throws -> ReleaseInfo
}

/// Unauthenticated `GET releases/latest`. GitHub allows 60 such requests an hour per IP; this app makes one a day.
struct GitHubReleaseSource: ReleaseSource {
    static let endpoint = URL(string: "https://api.github.com/repos/jens-wedin/sonos-remote/releases/latest")!

    private let session: URLSession
    private let userAgentVersion: String

    init(session: URLSession = .shared, userAgentVersion: String) {
        self.session = session
        self.userAgentVersion = userAgentVersion
    }

    func makeRequest() -> URLRequest {
        var request = URLRequest(url: Self.endpoint, timeoutInterval: 8)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("RemoteForSonos/\(userAgentVersion)", forHTTPHeaderField: "User-Agent")
        return request
    }

    func latest() async throws -> ReleaseInfo {
        let (data, response) = try await session.data(for: makeRequest())
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ReleaseSourceError.http(http.statusCode)
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try ReleaseInfo(wire: try decoder.decode(WireRelease.self, from: data))
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Same command as Step 2. Expected: `** TEST SUCCEEDED **`. If `url(forResource:)` returns nil, the fixture was not copied into the test bundle: confirm `SonosRemoteTests/Fixtures/github-release-latest.json` exists, rerun `xcodegen generate`, and check the generated project lists it under the test target's Copy Bundle Resources (`grep -c "github-release-latest.json" SonosRemote.xcodeproj/project.pbxproj` should print at least 2).

- [ ] **Step 5: Commit**

```bash
git add SonosRemote/App/ReleaseSource.swift SonosRemoteTests/ReleaseDecodingTests.swift
git commit -m "feat(updates): GitHub releases/latest source and decoder"
```
(End the message with the attribution lines from the Global Constraints.)

---

### Task 3: UpdateChecker

**Files:**
- Create: `SonosRemote/App/UpdateChecker.swift`
- Test: `SonosRemoteTests/UpdateCheckerTests.swift`

**Interfaces:**
- Consumes: `SemanticVersion.isNewer(_:than:)` (Task 1); `ReleaseInfo`, `ReleaseSource`, `ReleaseSourceError`, `GitHubReleaseSource(userAgentVersion:)` (Task 2); `AppVersion.short` (exists, `SonosRemote/App/AppVersion.swift`).
- Produces: `@MainActor @Observable final class UpdateChecker` with
  - `private(set) var available: ReleaseInfo?` — newer than the running version and not dismissed.
  - `private(set) var latestKnown: ReleaseInfo?` — newest newer release seen, regardless of dismissal.
  - `var isEnabled: Bool` — stored, written through to UserDefaults `updateCheckEnabled`, default `true`; `false` cancels the timer and clears both releases, `true` restarts the timer and checks at once.
  - `let brewCommand = "brew upgrade --cask remote-for-sonos"`.
  - `func start()`, `func checkIfDue()`, `func check() async`, `func dismiss()`, `func copyCommand()`.
  - `init(source: any ReleaseSource, currentVersion: String, defaults: UserDefaults, pasteboard: NSPasteboard = .general, now: @escaping @Sendable () -> Date = Date.init, initialDelay: Duration = .seconds(30), interval: Duration = .seconds(86_400))`.
  - `static func live() -> UpdateChecker`.
  - `static let enabledKey = "updateCheckEnabled"`, `dismissedKey = "dismissedUpdateVersion"`, `lastCheckKey = "lastUpdateCheck"`, `static let checkInterval: TimeInterval = 86_400`.

Ruling carried from the plan header: `checkIfDue()` treats "no `lastUpdateCheck` recorded" as not due. The launch timer runs its unconditional check 30 s after start, so a fresh install is covered without a second request when the panel is opened in those first 30 s.

- [ ] **Step 1: Write the failing tests**

Create `SonosRemoteTests/UpdateCheckerTests.swift`:

```swift
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
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate
xcodebuild test -project SonosRemote.xcodeproj -scheme SonosRemote -destination 'platform=macOS' -derivedDataPath .build/xcode -only-testing:SonosRemoteTests/UpdateCheckerTests 2>&1 | grep -E "error:|TEST (SUCCEEDED|FAILED)" | head
```
Expected: `cannot find 'UpdateChecker' in scope`, `** TEST FAILED **`.

- [ ] **Step 3: Write the implementation**

Create `SonosRemote/App/UpdateChecker.swift`:

```swift
import AppKit
import Foundation
import Observation
import os

/// Asks the release source once a day whether a newer version exists and remembers the answer.
/// Failures never reach the user: they are logged and the next attempt waits a day.
@MainActor @Observable
final class UpdateChecker {
    static let enabledKey = "updateCheckEnabled"
    static let dismissedKey = "dismissedUpdateVersion"
    static let lastCheckKey = "lastUpdateCheck"
    static let checkInterval: TimeInterval = 86_400

    /// Newer than the running version and not dismissed; drives the main-screen card.
    private(set) var available: ReleaseInfo?
    /// Newest newer release seen, dismissed or not; drives the Settings version row.
    private(set) var latestKnown: ReleaseInfo?

    /// The "Check for updates" switch. Off cancels the timer and hides every notice; on restarts the timer and checks at once.
    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            defaults.set(isEnabled, forKey: Self.enabledKey)
            if isEnabled {
                start()
                Task { await check() }
            } else {
                timer?.cancel()
                timer = nil
                available = nil
                latestKnown = nil
            }
        }
    }

    let brewCommand = "brew upgrade --cask remote-for-sonos"

    @ObservationIgnored private let source: any ReleaseSource
    @ObservationIgnored private let currentVersion: String
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let pasteboard: NSPasteboard
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let initialDelay: Duration
    @ObservationIgnored private let interval: Duration
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var inFlight = false
    @ObservationIgnored private let logger = Logger(subsystem: "com.jenswedin.SonosRemote", category: "updates")

    init(
        source: any ReleaseSource,
        currentVersion: String,
        defaults: UserDefaults,
        pasteboard: NSPasteboard = .general,
        now: @escaping @Sendable () -> Date = Date.init,
        initialDelay: Duration = .seconds(30),
        interval: Duration = .seconds(86_400)
    ) {
        self.source = source
        self.currentVersion = currentVersion
        self.defaults = defaults
        self.pasteboard = pasteboard
        self.now = now
        self.initialDelay = initialDelay
        self.interval = interval
        self.isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    static func live() -> UpdateChecker {
        UpdateChecker(
            source: GitHubReleaseSource(userAgentVersion: AppVersion.short),
            currentVersion: AppVersion.short,
            defaults: .standard
        )
    }

    /// First check `initialDelay` after launch, then every `interval` while enabled. Safe to call more than once.
    func start() {
        guard isEnabled, timer == nil else { return }
        let delay = initialDelay
        let every = interval
        timer = Task { [weak self] in
            try? await Task.sleep(for: delay)
            while !Task.isCancelled, let self {
                await self.check()
                try? await Task.sleep(for: every)
            }
        }
    }

    /// The panel calls this on open: runs a check only when the last recorded one is older than a day.
    /// No recorded check means the launch timer has not run yet; it will, so nothing happens here.
    func checkIfDue() {
        guard isEnabled, let last = defaults.object(forKey: Self.lastCheckKey) as? Date,
              now().timeIntervalSince(last) >= Self.checkInterval else { return }
        Task { await check() }
    }

    /// One fetch. Success updates the notices; any failure is logged and leaves them unchanged.
    /// `lastUpdateCheck` is written either way so a failing endpoint is not retried before tomorrow.
    func check() async {
        guard isEnabled, !inFlight else { return }
        inFlight = true
        defer { inFlight = false }
        do {
            apply(try await source.latest())
        } catch {
            logger.info("update check failed: \(String(describing: error), privacy: .public)")
        }
        defaults.set(now(), forKey: Self.lastCheckKey)
    }

    func dismiss() {
        guard let available else { return }
        defaults.set(available.version, forKey: Self.dismissedKey)
        self.available = nil
    }

    func copyCommand() {
        pasteboard.clearContents()
        pasteboard.setString(brewCommand, forType: .string)
    }

    private func apply(_ release: ReleaseInfo) {
        guard SemanticVersion.isNewer(release.version, than: currentVersion) else {
            available = nil
            latestKnown = nil
            return
        }
        latestKnown = release
        available = release.version == defaults.string(forKey: Self.dismissedKey) ? nil : release
    }
}
```

Notes for the implementer:
- `@Observable` tracks stored properties; `isEnabled` is stored (with `didSet`) so the Settings switch re-renders when it changes. The `@ObservationIgnored` members are plumbing the views never read.
- `Task { … }` created inside a `@MainActor` method inherits main-actor isolation, so `self.check()` inside the timer needs no hop. `while !Task.isCancelled, let self` rebinds the weak capture per iteration so a cancelled or deallocated checker ends the loop.
- `NSPasteboard` is not `Sendable`; it is only ever touched from the main actor, which is why it is a stored property of a `@MainActor` class rather than a global.
- If `isEnabled`'s `didSet` and `@Observable` do not compile together on this toolchain (Xcode 26 accepts them), fall back to a private stored `enabled` property plus a computed `isEnabled` whose getter reads `enabled` and whose setter runs the same body.

- [ ] **Step 4: Run the tests to verify they pass**

Same command as Step 2. Expected `** TEST SUCCEEDED **`. If a `waitUntil` test is flaky, raise its loop count; do not remove the test.

- [ ] **Step 5: Run the whole app test target once**

```bash
xcodebuild test -project SonosRemote.xcodeproj -scheme SonosRemote -destination 'platform=macOS' -derivedDataPath .build/xcode 2>&1 | grep -E "error:|Executed|TEST (SUCCEEDED|FAILED)" | tail -4
```
Expected: `** TEST SUCCEEDED **`; the executed count is the previous count plus the new tests from Tasks 1–3 (8 + 6 + 12 = 26).

- [ ] **Step 6: Commit**

```bash
git add SonosRemote/App/UpdateChecker.swift SonosRemoteTests/UpdateCheckerTests.swift
git commit -m "feat(updates): daily update checker with dismissal and opt-out"
```
(End the message with the attribution lines from the Global Constraints.)

---

### Task 4: UpdateCard and the main screen

**Files:**
- Create: `SonosRemote/Views/Components/UpdateCard.swift`
- Modify: `SonosRemote/Views/Main/MainScreen.swift` (whole file shown below)
- Modify: `SonosRemote/App/SonosRemoteApp.swift` (whole file shown below) — the checker must be in the environment before `MainScreen` can read it, so the app wiring lands here rather than in Task 5.

**Interfaces:**
- Consumes: `UpdateChecker` (`available`, `copyCommand()`, `dismiss()`, `start()`, `live()`), `ReleaseInfo` (`version`, `notesURL`), `AppState.announce(_:)` (exists), `Palette.border(_:)`, `Color.supporting` (exist in `Palette.swift`).
- Produces: `struct UpdateCard: View { init(release: ReleaseInfo, onCopy: @escaping () -> Void, onDismiss: @escaping () -> Void) }`; `struct CopyCommandButton: View { init(onCopy: @escaping () -> Void) }` (same file, reused by Task 5); `SonosRemoteApp` injects `UpdateChecker` with `.environment(updates)` so every screen can read `@Environment(UpdateChecker.self)`.

- [ ] **Step 1: Create the card view**

Create `SonosRemote/Views/Components/UpdateCard.swift`:

```swift
import SwiftUI

/// "Update available" notice at the top of the main screen: version, copy-the-brew-command, what's new, dismiss.
struct UpdateCard: View {
    let release: ReleaseInfo
    let onCopy: () -> Void
    let onDismiss: () -> Void

    @Environment(AppState.self) private var state
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var announcedVersion: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "arrow.down")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 40, height: 40)
                .background(Color.accentColor.opacity(0.18), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: "Update available — v\(release.version)")
                    .font(.callout.weight(.semibold))
                HStack(spacing: 14) {
                    CopyCommandButton(onCopy: onCopy)

                    Link(destination: release.notesURL) {
                        Label("What's new", systemImage: "arrow.up.right")
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(Color.supporting)
                    .focusable()
                    .accessibilityLabel(Text(verbatim: "Show what's new in v\(release.version)"))
                }
            }

            Spacer(minLength: 0)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.supporting)
            .focusable()
            .accessibilityLabel("Dismiss update notice")
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.border(contrast).opacity(0.6)))
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .accessibilityElement(children: .contain)
        .onAppear(perform: announceOnce)
        .onChange(of: release.version) { announceOnce() }
    }

    private func announceOnce() {
        guard announcedVersion != release.version else { return }
        announcedVersion = release.version
        state.announce("Update available, version \(release.version)")
    }
}

/// "Copy Homebrew command" that reads "Copied" for two seconds after a click and announces it.
/// Shared by the update card and the Settings version row.
struct CopyCommandButton: View {
    let onCopy: () -> Void

    @Environment(AppState.self) private var state
    @State private var copied = false

    var body: some View {
        Button {
            onCopy()
            copied = true
            state.announce("Copied")
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                copied = false
            }
        } label: {
            Label(copied ? "Copied" : "Copy Homebrew command", systemImage: copied ? "checkmark" : "doc.on.doc")
                .font(.caption.weight(.medium))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
        .focusable()
        .accessibilityLabel("Copy Homebrew upgrade command")
    }
}
```

- [ ] **Step 2: Render it on the main screen**

Replace `SonosRemote/Views/Main/MainScreen.swift` with:

```swift
import SwiftUI
import SonosKit

struct MainScreen: View {
    @Environment(AppState.self) private var state
    @Environment(UpdateChecker.self) private var updates
    let focus: FocusState<PanelFocus?>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StatusBannerView()
            if let release = updates.available {
                UpdateCard(release: release, onCopy: { updates.copyCommand() }, onDismiss: { updates.dismiss() })
            }
            HeroView(group: state.selectedGroup)
            if let group = state.selectedGroup {
                ProgressBarView(group: group)
            }
            TransportView(group: state.selectedGroup, focus: focus)
            if let group = state.selectedGroup {
                VolumeRowView(group: group)
            }
            if !state.groups.isEmpty {
                RoomsListView()
            }
        }
        .padding(.bottom, 12)
    }
}
```

- [ ] **Step 3: Create, start and inject the checker at launch**

Replace `SonosRemote/App/SonosRemoteApp.swift` with:

```swift
import SwiftUI
import SonosKit
import MenuBarExtraAccess
import KeyboardShortcuts

@main
struct SonosRemoteApp: App {
    @State private var appState: AppState
    @State private var panel: PanelController
    @State private var updates: UpdateChecker

    init() {
        let panel = PanelController()
        _panel = State(initialValue: panel)
        let appState = AppState.live()
        _appState = State(initialValue: appState)
        appState.start()
        let updates = UpdateChecker.live()
        _updates = State(initialValue: updates)
        updates.start()
        KeyboardShortcuts.onKeyUp(for: .togglePanel) {
            Task { @MainActor in panel.toggle() }
        }
    }

    var body: some Scene {
        MenuBarExtra("Sonos", systemImage: "hifispeaker.2") {
            PanelShellView(closePanel: { panel.close() })
                .environment(appState)
                .environment(panel)
                .environment(updates)
        }
        .menuBarExtraAccess(isPresented: $panel.isPresented)
        .menuBarExtraStyle(.window)
    }
}
```

- [ ] **Step 4: Build and run the tests**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate
xcodebuild test -project SonosRemote.xcodeproj -scheme SonosRemote -destination 'platform=macOS' -derivedDataPath .build/xcode 2>&1 | grep -E "error:|warning: .*UpdateCard|TEST (SUCCEEDED|FAILED)" | tail -5
```
Expected: no `error:` lines, `** TEST SUCCEEDED **`. There is no unit test for the view; the manual check is in Task 6.

- [ ] **Step 5: Self-check the accessibility contract against the file**

```bash
grep -c "focusable()" SonosRemote/Views/Components/UpdateCard.swift            # expect 3
grep -c "accessibilityLabel" SonosRemote/Views/Components/UpdateCard.swift      # expect 3
grep -c "\.secondary" SonosRemote/Views/Components/UpdateCard.swift             # expect 0
grep -c "Text(verbatim:" SonosRemote/Views/Components/UpdateCard.swift          # expect 2
```

- [ ] **Step 6: Commit**

```bash
git add SonosRemote/Views/Components/UpdateCard.swift SonosRemote/Views/Main/MainScreen.swift SonosRemote/App/SonosRemoteApp.swift
git commit -m "feat(updates): update card on the main screen, checker wired at launch"
```
(End the message with the attribution lines from the Global Constraints.)

---

### Task 5: Settings rows and the panel-open check

**Files:**
- Modify: `SonosRemote/Views/Settings/SettingsScreen.swift` (GENERAL card lines 36–55, SYSTEM card lines 57–77)
- Modify: `SonosRemote/Views/Shell/PanelShellView.swift` (add one environment property and one line in the `onChange` at line 32)

**Interfaces:**
- Consumes: `UpdateChecker` (`isEnabled` get/set, `latestKnown`, `copyCommand()`, `checkIfDue()`) injected in Task 4; `CopyCommandButton(onCopy:)` from Task 4.
- Produces: nothing new.

- [ ] **Step 1: Add the environment property and the "Check for updates" row**

In `SonosRemote/Views/Settings/SettingsScreen.swift`, below `@Environment(AppState.self) private var state` add:

```swift
    @Environment(UpdateChecker.self) private var updates
```

At the top of `body`, before the outer `VStack(alignment: .leading, spacing: 0) {`, add the local binding the repo already uses in `FavoritesScreen` and `SoundScreen`:

```swift
        @Bindable var updates = updates
```

In the GENERAL `Card`, after the `Global shortcut` `CardRow` (the one containing `KeyboardShortcuts.Recorder`) and before the card's closing brace, add:

```swift
                CardRow {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Check for updates").font(.callout).accessibilityHidden(true)
                        Text("Asks github.com once a day").font(.caption).foregroundStyle(Color.supporting).accessibilityHidden(true)
                    }
                    Spacer()
                    Toggle("Check for updates", isOn: $updates.isEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .accessibilityHint("Asks github.com once a day")
                }
```

- [ ] **Step 2: Extend the Version row**

Replace the SYSTEM card's first `CardRow` (the one showing `AppVersion.display`) with:

```swift
                CardRow(isFirst: true) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Version").font(.callout)
                        if let release = updates.latestKnown {
                            Text(verbatim: "Update available: \(release.version)")
                                .font(.caption).foregroundStyle(Color.supporting)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(AppVersion.display).font(.callout.monospacedDigit()).foregroundStyle(Color.supporting)
                        if updates.latestKnown != nil {
                            CopyCommandButton(onCopy: { updates.copyCommand() })
                        }
                    }
                }
```

- [ ] **Step 3: Check on panel open**

In `SonosRemote/Views/Shell/PanelShellView.swift`, below `@Environment(PanelController.self) private var panel` add:

```swift
    @Environment(UpdateChecker.self) private var updates
```

and replace the line

```swift
        .onChange(of: panel.isPresented, initial: true) { _, presented in state.setPanelPresented(presented) }
```

with

```swift
        .onChange(of: panel.isPresented, initial: true) { _, presented in
            state.setPanelPresented(presented)
            if presented { updates.checkIfDue() }
        }
```

- [ ] **Step 4: Build and run the tests**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild test -project SonosRemote.xcodeproj -scheme SonosRemote -destination 'platform=macOS' -derivedDataPath .build/xcode 2>&1 | grep -E "error:|TEST (SUCCEEDED|FAILED)" | tail -3
```
Expected: `** TEST SUCCEEDED **`, no `error:` lines. (No files were added, so `xcodegen generate` is not needed.)

- [ ] **Step 5: Self-check**

```bash
grep -n "Check for updates\|Asks github.com once a day\|Update available:\|CopyCommandButton" SonosRemote/Views/Settings/SettingsScreen.swift
grep -n "checkIfDue" SonosRemote/Views/Shell/PanelShellView.swift
grep -c "\.secondary" SonosRemote/Views/Settings/SettingsScreen.swift   # expect 0
```
Expected: each string appears; `checkIfDue` appears once.

- [ ] **Step 6: Commit**

```bash
git add SonosRemote/Views/Settings/SettingsScreen.swift SonosRemote/Views/Shell/PanelShellView.swift
git commit -m "feat(updates): check-for-updates switch, version row notice, check on panel open"
```
(End the message with the attribution lines from the Global Constraints.)

---

### Task 6: Documentation

**Files:**
- Modify: `README.md` (Features list line 26, "Not yet" line 31, "How it works" section after line 39, new "Updating" section after "Install")
- Modify: `changelog.md` (under `## [Unreleased]`)
- Modify: `knowledge/procedural/manual-test-checklist.md` (append item 14)
- Create: `knowledge/domain/github-releases-api.md`
- Modify: `knowledge/INDEX.md`

**Interfaces:** none.

- [ ] **Step 1: README**

In `README.md`:

1. Under `## Install`, after the paragraph beginning "The app talks to the speakers through Sonos's local Control API", add:

```markdown
## Updating

The panel shows an "Update available" card when a newer release exists. Click "Copy Homebrew command" and paste it in Terminal:

    brew upgrade --cask remote-for-sonos

If you installed from the zip, download the new zip from the Releases page instead. The card can be dismissed per version; Settings still shows the available version.
```

2. In the `## Features (v0.2.0)` list, change the Settings bullet to:

```markdown
- Settings screen: connection status with refresh, launch at login, a global shortcut, a "Check for updates" switch, version (with the available update) and a link to releases.
```

3. In `### Not yet`, remove `, in-app update checks` so the sentence reads `Seeking by dragging the progress bar, balance, Speech Enhancement and Night Sound, pinned favorites, album art in the menu bar. See ...`.

4. At the end of `## How it works`, add a paragraph:

```markdown
Once a day the app asks github.com for the latest release so it can tell you when an update exists; switch it off under Settings → Check for updates. Nothing else leaves your network.
```

- [ ] **Step 2: Changelog**

Under `## [Unreleased]` in `changelog.md` add:

```markdown
### Added
- The panel tells you when a newer release exists: an "Update available" card with a copyable `brew upgrade --cask remote-for-sonos` command and a "What's new" link, dismissable per version; Settings shows the available version and has a "Check for updates" switch (on by default, one request to github.com a day).
```

- [ ] **Step 3: Manual checklist**

Append to `knowledge/procedural/manual-test-checklist.md`:

```markdown
14. Updates: build with `MARKETING_VERSION` set below the latest release (`xcodebuild … MARKETING_VERSION=0.0.1`); within 30 s of launch the main screen shows "Update available — v<latest>". "Copy Homebrew command" swaps to "Copied" and pasting in Terminal gives `brew upgrade --cask remote-for-sonos`; "What's new" opens the release page; X hides the card and Settings → Version still says "Update available: <latest>" with the copy button. Switch "Check for updates" off → the card and the Settings line disappear; on again → they return. VoiceOver announces "Update available, version <latest>" once and reads the three buttons by name.
```

- [ ] **Step 4: Knowledge note and index**

Create `knowledge/domain/github-releases-api.md`:

```markdown
# GitHub Releases API (update check)

- Endpoint: `GET https://api.github.com/repos/jens-wedin/sonos-remote/releases/latest`, unauthenticated. Returns the newest release that is neither a draft nor a pre-release; 404 when the repository has no release.
- Headers sent: `Accept: application/vnd.github+json`, `User-Agent: RemoteForSonos/<version>` (GitHub rejects requests without a User-Agent with 403).
- Rate limit: 60 requests an hour per IP for unauthenticated calls (`X-RateLimit-Remaining` in the response). The app makes one a day: 30 s after launch, every 24 h, and on panel open when the last check is older than 24 h.
- Fields read: `tag_name` (`vX.Y.Z`, the release script's format), `html_url` (release page, used for "What's new"), `draft`, `prerelease`, `name`, `body`. Everything else is ignored. Fixture: `SonosRemoteTests/Fixtures/github-release-latest.json`, captured 2026-09-12 with `gh api repos/jens-wedin/sonos-remote/releases/latest`.
- Code: `SonosRemote/App/ReleaseSource.swift` (decoder, HTTP), `SonosRemote/App/UpdateChecker.swift` (policy; UserDefaults `updateCheckEnabled`, `dismissedUpdateVersion`, `lastUpdateCheck`), `SonosRemote/App/SemanticVersion.swift` (compare).
```

In `knowledge/INDEX.md`, after the `domain/sonos-local-api.md` line add:

```markdown
- `domain/github-releases-api.md` — the GitHub `releases/latest` endpoint the update check uses: headers, rate limit, fields, where the code lives.
```

- [ ] **Step 5: Verify**

```bash
grep -n "Updating\|Check for updates\|github.com" README.md | head
grep -n "Update available" changelog.md knowledge/procedural/manual-test-checklist.md
grep -n "github-releases-api" knowledge/INDEX.md
```
Expected: each grep prints at least one line.

- [ ] **Step 6: Commit**

```bash
git add README.md changelog.md knowledge/procedural/manual-test-checklist.md knowledge/domain/github-releases-api.md knowledge/INDEX.md
git commit -m "docs: describe the update notice, privacy sentence, checklist and API note"
```
(End the message with the attribution lines from the Global Constraints.)

---

## Done when

- All six tasks committed on the feature branch; `xcodebuild test` reports `** TEST SUCCEEDED **` with 26 new tests (8 semantic version, 6 decoding, 12 checker).
- `git status` shows no `SonosRemote.xcodeproj`, `.build/` or `.superpowers/` changes staged.
- The owner runs manual check 14 before the release.
