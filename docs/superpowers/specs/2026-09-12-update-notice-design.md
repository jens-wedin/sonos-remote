# Update notice: design spec

Date: 2026-09-12. Status: approved in conversation (owner: Jens). Builds on the v0.2.1 codebase (`docs/superpowers/specs/2026-09-11-panel-redesign-design.md` for the panel, `docs/audits/2026-09-11-fix-round-1.md` for the accessibility tokens and announcement helpers it reuses).

## 1. Goal

Tell the user, inside the panel, when a newer release of Remote for Sonos exists, and show them how to get it. The app is installed either through the Homebrew cask `jens-wedin/tap/remote-for-sonos` or from the release zip; both are updated with `brew update && brew upgrade --cask remote-for-sonos` or by downloading the new zip. The app is sandboxed and cannot run `brew` itself, so the notice guides rather than installs.

### In scope

- A daily check of the latest GitHub release, comparing semantic versions with the running app.
- A dismissable card at the top of the main screen with the new version, a "Copy Homebrew command" action and a "What's new" link.
- The Settings screen's Version row showing the available version with the same copy action, so a dismissed notice stays findable.
- A "Check for updates" switch in Settings (default on) and a privacy sentence in the README.
- Unit tests for the version comparison, the check policy and the decoder; a manual check for the card.

### Out of scope (later, without changing this design)

In-place updating (Sparkle), a badge on the menu bar icon, macOS notifications, checking pre-releases, checking more often than daily.

## 2. Decisions

| Decision | Choice | Why |
|---|---|---|
| Update path | Guided via Homebrew | The sandbox forbids running `brew`; a guided notice works for both install paths with no new dependency |
| Source | `GET https://api.github.com/repos/jens-wedin/sonos-remote/releases/latest` | Public, unauthenticated, excludes drafts and pre-releases; the 60 requests/hour per IP limit is far above one request a day |
| Frequency | 30 s after launch, then every 24 h while running, and on panel open when the last check is older than 24 h | Cheap, and a user who opens the panel after days away sees the notice on the next open |
| Comparison | Semantic `major.minor.patch`, strictly newer than `CFBundleShortVersionString`; a leading `v` in the tag is stripped; tags that do not parse are ignored | Matches the release script's `vX.Y.Z` tags |
| Placement | Card on the main screen; Version row in Settings | Chosen by the owner; visible in the flow, quiet elsewhere |
| Dismissal | Per version: the X hides the card until a newer version appears | A user who has decided not to update is not nagged; the Settings row still shows it |
| Opt-out | "Check for updates" switch, default on, caption "Asks github.com once a day" | The README promises nothing leaves the home; the check is disclosed and can be turned off |
| Failure | Any error leaves the app unchanged and is logged at info level | An update notice must never block or degrade the panel |

## 3. Components

All new code lives in the app target; SonosKit is untouched.

`SonosRemote/App/UpdateChecker.swift`

- `struct ReleaseInfo: Hashable, Sendable { let version: String; let tag: String; let notesURL: URL }` decoded from the API's `tag_name` and `html_url` (`WireRelease: Decodable`; `body`, `name`, `draft`, `prerelease` are read but unused apart from ignoring `draft || prerelease`).
- `protocol ReleaseSource: Sendable { func latest() async throws -> ReleaseInfo }` with `struct GitHubReleaseSource: ReleaseSource` over a `URLSession` (8 s request timeout, `Accept: application/vnd.github+json`, `User-Agent: RemoteForSonos/<version>`); a non-2xx status throws `ReleaseSourceError.http(Int)`.
- `enum SemanticVersion { static func parse(_ string: String) -> (Int, Int, Int)?; static func isNewer(_ candidate: String, than current: String) -> Bool }` — pure; missing minor/patch count as 0; anything after the numbers (a pre-release suffix) makes the version not parse and therefore never "newer".
- `@MainActor @Observable final class UpdateChecker`:
  - `private(set) var available: ReleaseInfo?` — the newest release that is newer than the running version and not dismissed.
  - `var isEnabled: Bool` (UserDefaults `updateCheckEnabled`, default `true`); setting it to `false` clears `available` and cancels the timer; setting it to `true` checks immediately.
  - `func start()` — schedules the first check 30 s after launch and a repeating check every 24 h while enabled.
  - `func checkIfDue()` — runs a check when enabled and `lastUpdateCheck` (UserDefaults) is older than 24 h; the panel calls it on open.
  - `func check() async` — fetches, ignores drafts/pre-releases, sets `available` when `SemanticVersion.isNewer(release.version, than: currentVersion)` and `release.version != dismissedVersion`, updates `lastUpdateCheck` on success or failure (so a failing endpoint is not hammered), logs failures.
  - `func dismiss()` — stores `dismissedUpdateVersion = available?.version` and clears `available`.
  - `var brewCommand: String { "brew update && brew upgrade --cask remote-for-sonos" }` and `func copyCommand()` (NSPasteboard, general pasteboard).
  - `init(source: any ReleaseSource, currentVersion: String, defaults: UserDefaults, now: @escaping () -> Date, initialDelay: Duration, interval: Duration)`; `static func live() -> UpdateChecker` uses `GitHubReleaseSource`, `AppVersion.short`, `.standard`, `Date.init`, 30 s and 24 h.

`SonosRemote/Views/Components/UpdateCard.swift`

- `UpdateCard(release: ReleaseInfo, onCopy: () -> Void, onDismiss: () -> Void)`; layout: 40 pt tinted rounded square with `arrow.down` on the left; title `Update available — v<version>` in semibold (`Text(verbatim:)`); a second row with two plain buttons, "Copy Homebrew command" (label swaps to "Copied" for two seconds, announced) and "What's new" (a `Link` to `notesURL`, opens in the browser); an X button on the right. Card look: `Card` background, `Palette.border`; text in `Color.primary` / `Color.supporting`.
- Accessibility: the card is a container (`children: .contain`); buttons labelled "Copy Homebrew upgrade command", "Show what's new in v<version>", "Dismiss update notice"; all three `.focusable()`; on first appearance for a version the view calls `state.announce("Update available, version <version>")` once per app session (the checker remembers announced versions in `shouldAnnounce(_:)`; view state would reset on every screen switch).

`SonosRemote/Views/Main/MainScreen.swift`: `UpdateCard` rendered between `StatusBannerView` and `HeroView` when `updates.available != nil`.

`SonosRemote/Views/Settings/SettingsScreen.swift`: GENERAL card gains a "Check for updates" row (title, caption "Asks github.com once a day", switch bound to `updates.isEnabled`); the SYSTEM Version row shows a second line "Update available: <version>" with a "Copy Homebrew command" button when `updates.latestKnown` exists (so it stays visible after the card was dismissed — see §4).

`SonosRemote/App/SonosRemoteApp.swift`: creates `UpdateChecker.live()`, calls `start()`, injects it with `.environment(updates)`; `PanelShellView` calls `updates.checkIfDue()` when `panel.isPresented` becomes true.

## 4. Data flow and state

- `available` drives the main-screen card. Dismissal clears it and records the version; a later check that finds the same version keeps it cleared, a newer version sets it again.
- For Settings, a second read-only property `latestKnown: ReleaseInfo?` keeps the last newer release seen regardless of dismissal, so the Version row can still say "Update available: 0.2.2" after the card was dismissed. `latestKnown` clears when the running version catches up (after the user updates and relaunches, the check finds nothing newer).
- UserDefaults keys: `updateCheckEnabled` (Bool), `dismissedUpdateVersion` (String), `lastUpdateCheck` (Date).
- The 24 h timer is a `Task` on the main actor with `Task.sleep(for:)`, cancelled when disabled; `retryDiscovery` and panel state do not affect it.

## 5. Error handling

Network failure, timeout, HTTP 403/404/5xx, malformed JSON, a draft or pre-release, and an unparsable tag all result in no change to `available`, a `Logger` line at info level (subsystem `com.jenswedin.SonosRemote`, category `updates`), and `lastUpdateCheck` set so the next attempt is a day away. Nothing is shown to the user for failures.

## 6. Testing

Unit tests in `SonosRemoteTests`:
- `SemanticVersionTests`: `isNewer("0.2.2", than: "0.2.1")`, equal is not newer, `"v0.3.0"` vs `"0.2.9"`, `"1.0"` treated as `1.0.0`, `"0.3.0-beta.1"` never newer, garbage never newer.
- `UpdateCheckerTests` with a `FakeReleaseSource` (returns a fixed release or throws) and an injected clock: newer release → `available` set; same or older → nil; dismissed version stays nil on the next check, a newer one shows; disabled → the source is never called and `available` is nil; `checkIfDue` skips within 24 h and runs after; a throwing source leaves `available` nil and still updates `lastUpdateCheck`; drafts and pre-releases ignored.
- `ReleaseDecodingTests`: decodes a captured `releases/latest` JSON fixture (`SonosRemoteTests/Fixtures/github-release-latest.json`, taken from the real repository with `gh api`) into `ReleaseInfo`.
- Manual (owner): build with `MARKETING_VERSION` temporarily set below the latest release, confirm the card, copy the command and paste it in Terminal, follow "What's new", dismiss, confirm the Settings row still shows it; switch "Check for updates" off and confirm the row and card disappear.

## 7. Documentation

README: a sentence under "How it works" or a privacy note ("Once a day the app asks github.com for the latest release so it can tell you when an update exists; switch it off under Settings → Check for updates. Nothing else leaves your network."), and an "Updating" section with the brew command. `changelog.md` under Unreleased. Manual checklist gains the steps above. `knowledge/domain/` gets a short note on the GitHub Releases endpoint and rate limit.
