# Panel Redesign Round 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the panel to the owner's mockup: a hero for one selected room with progress and full transport, a compact rooms list, and Favorites, Sound, Group, and Settings screens reached from header icons, keeping every feature the app has today.

**Architecture:** One `Screen` enum in `AppState` drives a shell view that swaps screen views with a slide; one `selectedGroupID` replaces the old open-row model. SonosKit grows a small `PlaybackProgress` (position, duration, shuffle, repeat) filled by the reducer from events it already receives, plus one play-mode command. All new app logic (selection, presets, filtering, progress display) is pure and unit tested; views are thin.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI on macOS 26, Swift Testing, XcodeGen, existing SonosKit package (`Packages/SonosKit`), MenuBarExtraAccess, KeyboardShortcuts, ServiceManagement.

**Spec:** `docs/superpowers/specs/2026-09-11-panel-redesign-design.md`. Mockup: `docs/design/2026-09-11-panel-mockup.png`. The original architecture spec still applies: `docs/superpowers/specs/2026-09-04-sonos-remote-design.md`.

## Global Constraints

- Swift language mode 6 with strict concurrency in every target; builds warning-free from our own files.
- Panel width exactly `420` pt. Content height animates; the body scrolls beyond `640` pt.
- Header label on the main screen is the uppercase text `SONOS`; sub-screen titles are `FAVORITES`, `SOUND`, `GROUP`, `SETTINGS`. Footer text is `Remote for Sonos <CFBundleShortVersionString>` and `Quit`.
- Tone presets, exact values: Flat bass 0 treble 0; Warm bass +3 treble −2; Bright bass −2 treble +3. Reset writes bass 0, treble 0, and sub 0 when the player has a sub.
- Progress display: remaining time is shown with a leading minus sign (`−3:08`); times use `m:ss`; when duration is unknown the bar and both times are hidden.
- Screen names: `main`, `favorites`, `sound`, `group`, `settings`. Slide transition duration `0.2` s.
- `selectedGroupID` persists under the UserDefaults key `selectedGroupID`. There is no "nothing selected" state while groups exist.
- Views refer to SonosKit's `Group` as `SonosGroup` (typealias in `SonosRemote/App/SonosGroupAlias.swift`) because SwiftUI's `Group` shadows it in files that import both.
- Every `swift` command runs from `Packages/SonosKit`; every `xcodegen`/`xcodebuild` command from the repo root; all with `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. Never `sudo xcode-select`. Run `xcodegen generate` after adding or deleting Swift files. Never commit `SonosRemote.xcodeproj`, `.build/`, `.superpowers/`.
- Quit the running app before rebuilding (`pkill -x SonosRemote`) and relaunch after (`open .build/xcode/Build/Products/Debug/SonosRemote.app`).
- Do not exercise the owner's speakers from scripts (no `sonosctl` commands that change state, no automated clicking); the visual checks listed per task are for the owner.
- Conventional commits; commit at the end of every task.
- Test commands: package `swift test` (currently 71 tests); app `xcodebuild test -project SonosRemote.xcodeproj -scheme SonosRemote -destination 'platform=macOS' -derivedDataPath .build/xcode 2>&1 | grep -E "error:|Test run with|TEST (SUCCEEDED|FAILED)" | tail -3` (currently 17 tests). Build: `xcodebuild -project SonosRemote.xcodeproj -scheme SonosRemote -configuration Debug -derivedDataPath .build/xcode build 2>&1 | grep -E "error:|warning: .*SonosRemote/|BUILD" | head`.

---

## File Structure

```
Packages/SonosKit/Sources/SonosKit/
  Models/Models.swift                 + PlaybackProgress; Group.progress; Favorite.kind
  Models/HouseholdSnapshot.swift      + softwareVersion
  Wire/WireTypes.swift                + playModes, availablePlaybackActions, positionMillis, durationMillis, resource.type, softwareVersion
  Wire/WireMapping.swift              + Favorite.Kind mapping
  Socket/SocketFrame.swift            playbackStatus and metadata events carry the new fields
  Reducer/HouseholdEvent.swift        playbackStatus(groupID:state:progress:), metadata(groupID:nowPlaying:durationMillis:)
  Reducer/SnapshotReducer.swift       fills Group.progress; keeps softwareVersion
  LocalAPI/LocalAPIClient.swift       + setPlayModes(shuffle:repeat:groupID:at:)
  Household/Household.swift           + setShuffle/setRepeat; clock injection for reportedAt

SonosRemote/App/
  Screen.swift                        enum Screen
  SelectionPolicy.swift               renamed from RowOpenPolicy
  PlaybackDisplay.swift               displayedPosition, time formatting (pure)
  TonePreset.swift                    presets + matching (pure)
  FavoritesFilter.swift               search filter (pure)
  AppState.swift                      selectedGroupID, screen, per-screen state, tick, new commands
  AppVersion.swift                    short / display version strings (Task 9)
  SonosRemoteApp.swift                shell only; Window scene removed
SonosRemote/Views/
  Shell/PanelShellView.swift          header + animated body + footer + keyboard
  Shell/HeaderView.swift
  Shell/FooterView.swift              moved from Views/FooterView.swift
  Components/SectionLabel.swift, Card.swift, RoomPicker.swift, IconButton.swift (Task 4), ErrorLine.swift (Task 5), SearchField.swift (Task 6)
  Main/MainScreen.swift, HeroView.swift, ProgressBarView.swift, TransportView.swift (moved from Views/, rewritten), VolumeRowView.swift, RoomsListView.swift, RoomRowView.swift
  Favorites/FavoritesScreen.swift, FavoriteRow.swift
  Sound/SoundScreen.swift, PresetChips.swift, ToneSlider.swift
  Group/GroupScreen.swift
  Settings/SettingsScreen.swift
  (modified) VolumeSliderView.swift (style variants), Artwork.swift (placeholder glyph), StatusBannerView.swift (card look)
  (kept) SonosGroupAlias.swift
  (deleted) PanelView.swift, OpenRowView.swift, ClosedRowView.swift, GroupRowView.swift, FavoritesTabView.swift, EQTabView.swift, GroupTabView.swift, SettingsView.swift, App/SettingsOpener.swift, App/RowOpenPolicy.swift
SonosRemoteTests/
  SelectionPolicyTests.swift (renamed), PlaybackDisplayTests.swift, TonePresetTests.swift, FavoritesFilterTests.swift, AppStateTests.swift (updated)
```

**Interfaces every task relies on** (defined in Tasks 1–3):

```swift
// SonosKit (Task 1–2)
public struct PlaybackProgress: Hashable, Sendable {
    public var positionMillis: Int; public var durationMillis: Int?; public var reportedAt: Date
    public var shuffle: Bool; public var repeatEnabled: Bool; public var canShuffle: Bool; public var canRepeat: Bool
    public static let none: PlaybackProgress   // zeros, reportedAt = .distantPast
}
public struct Group { …existing…; public var progress: PlaybackProgress }
public struct Favorite { …existing…; public var kind: Kind }   // enum Kind: station, playlist, album, other
public struct HouseholdSnapshot { …existing…; public var softwareVersion: String? }
extension Household { public func setShuffle(_ on: Bool, group: String) async throws; public func setRepeat(_ on: Bool, group: String) async throws }

// App (Task 3)
enum Screen: Hashable { case main, favorites, sound, group, settings }   // title, systemImage
enum SelectionPolicy { static func resolve(remembered: String?, groups: [Group]) -> String? }
enum PlaybackDisplay {
    static func displayedPosition(progress: PlaybackProgress, state: PlaybackState, now: Date) -> Int?
    static func timeString(millis: Int) -> String            // "1:42"
    static func remainingString(position: Int, duration: Int) -> String   // "−3:08"
}
struct TonePreset: Hashable, Identifiable { let id: String; let name: String; let bass: Int; let treble: Int
    static let all: [TonePreset]; static func matching(_ eq: EQSettings) -> TonePreset? }
enum FavoritesFilter { static func apply(_ favorites: [Favorite], query: String) -> [Favorite] }
// AppState additions
var selectedGroupID: String?; var selectedGroup: Group?; var screen: Screen; func show(_ screen: Screen); func back()
var favoritesSearch: String; var favoritesTargetGroupID: String?; var soundPlayerID: String?
func select(_ groupID: String); func setShuffle(_:group:); func setRepeat(_:group:); func applyPreset(_:player:); func resetTone(player:)
var tick: Int (increments once per second while the selected group is playing and the panel is presented); func setPanelPresented(_:)
```

---

### Task 1: SonosKit progress, play modes, favorite kind, software version

**Files:**
- Modify: `Packages/SonosKit/Sources/SonosKit/Models/Models.swift`
- Modify: `Packages/SonosKit/Sources/SonosKit/Models/HouseholdSnapshot.swift`
- Modify: `Packages/SonosKit/Sources/SonosKit/Wire/WireTypes.swift`
- Modify: `Packages/SonosKit/Sources/SonosKit/Wire/WireMapping.swift`
- Modify: `Packages/SonosKit/Sources/SonosKit/Socket/SocketFrame.swift`
- Modify: `Packages/SonosKit/Sources/SonosKit/Reducer/HouseholdEvent.swift`
- Modify: `Packages/SonosKit/Sources/SonosKit/Reducer/SnapshotReducer.swift`
- Modify: `Packages/SonosKit/Sources/SonosKit/Household/Household.swift` (event mapping, clock)
- Test: `Packages/SonosKit/Tests/SonosKitTests/ModelsTests.swift`, `SocketFrameTests.swift`, `ReducerTests.swift`, `HouseholdTests.swift`

**Interfaces:**
- Consumes: existing wire types and reducer.
- Produces: `PlaybackProgress`, `Group.progress`, `Favorite.kind`/`Favorite.Kind`, `HouseholdSnapshot.softwareVersion`; `SocketEvent.playbackStatus(groupID:state:progress:)`, `SocketEvent.metadata(groupID:nowPlaying:durationMillis:)`; `HouseholdEvent.playbackStatus(groupID:state:progress:)`, `HouseholdEvent.metadata(groupID:nowPlaying:durationMillis:)`; `Household.Configuration.now: @Sendable () -> Date` (default `Date.init`) used to stamp `reportedAt`.

Fixture facts to assert: `events.jsonl` line 2 (`playbackStatus`) has `positionMillis 133000`, `playModes.shuffle false`, `playModes.repeat false`, `availablePlaybackActions.canShuffle true`, `canRepeat true`; line 4 (`metadataStatus`) has `currentItem.track.durationMillis 246000`; `favorites.json` item has `resource.type "STREAM"`; `groups.json` players all have `softwareVersion "96.1-79270"`.

- [ ] **Step 1: Write the failing tests**

Append to `ModelsTests.swift` inside the suite:
```swift
    @Test func favoriteKindComesFromResourceType() throws {
        let list = try decoder.decode(WireFavoritesList.self, from: Fixtures.data("favorites.json"))
        #expect(Favorite(wire: list.items[0]).kind == .station)
        #expect(Favorite.Kind(resourceType: "PLAYLIST") == .playlist)
        #expect(Favorite.Kind(resourceType: "ALBUM") == .album)
        #expect(Favorite.Kind(resourceType: nil) == .other)
        #expect(Favorite.Kind(resourceType: "TRACK") == .other)
    }

    @Test func playbackProgressDefaults() {
        #expect(PlaybackProgress.none.positionMillis == 0)
        #expect(PlaybackProgress.none.durationMillis == nil)
        #expect(!PlaybackProgress.none.shuffle && !PlaybackProgress.none.repeatEnabled)
        let group = Group(id: "g", name: "g", coordinatorID: "p", playerIDs: ["p"], playbackState: .idle, volume: .silent, nowPlaying: nil)
        #expect(group.progress == .none)
    }
```

Append to `SocketFrameTests.swift`:
```swift
    @Test func playbackStatusCarriesPositionAndPlayModes() throws {
        let line = Fixtures.lines("events.jsonl")[1]
        guard case .playbackStatus(_, let state, let progress) = try SocketFrameDecoder.decode(Data(line.utf8)) else { Issue.record("expected playbackStatus"); return }
        #expect(state == .playing)
        #expect(progress.positionMillis == 133000)
        #expect(progress.shuffle == false && progress.repeatEnabled == false)
        #expect(progress.canShuffle && progress.canRepeat)
        #expect(progress.durationMillis == nil)
    }

    @Test func metadataCarriesDuration() throws {
        let line = Fixtures.lines("events.jsonl")[3]
        guard case .metadata(_, let nowPlaying, let duration) = try SocketFrameDecoder.decode(Data(line.utf8)) else { Issue.record("expected metadata"); return }
        #expect(nowPlaying?.title == "Off the Wall")
        #expect(duration == 246000)
    }
```
And in the existing `decodesTheCapturedEventSequence` test, update the two pattern matches: `events[1]` must now be matched with `guard case .playbackStatus(let g, let s, _) = events[1]` and `#expect(g == gid && s == .playing)`; `events[3]` with `guard case .metadata(let metaGroup, let nowPlaying, _)`.

Append to `ReducerTests.swift`:
```swift
    @Test func playbackStatusFillsProgressAndMetadataFillsDuration() throws {
        var snapshot = SnapshotReducer.reduce(HouseholdSnapshot(), try topology())
        let at = Date(timeIntervalSince1970: 1_000)
        let reported = PlaybackProgress(positionMillis: 133000, durationMillis: nil, reportedAt: at, shuffle: true, repeatEnabled: false, canShuffle: true, canRepeat: true)
        snapshot = SnapshotReducer.reduce(snapshot, .playbackStatus(groupID: gid, state: .playing, progress: reported))
        #expect(snapshot.group(gid)?.progress.positionMillis == 133000)
        #expect(snapshot.group(gid)?.progress.shuffle == true)
        #expect(snapshot.group(gid)?.progress.reportedAt == at)
        snapshot = SnapshotReducer.reduce(snapshot, .metadata(groupID: gid, nowPlaying: NowPlaying(title: "Song"), durationMillis: 246000))
        #expect(snapshot.group(gid)?.progress.durationMillis == 246000)
        #expect(snapshot.group(gid)?.progress.positionMillis == 133000)
        // A later playback status keeps the duration from metadata.
        snapshot = SnapshotReducer.reduce(snapshot, .playbackStatus(groupID: gid, state: .paused, progress: PlaybackProgress(positionMillis: 140000, durationMillis: nil, reportedAt: at, shuffle: false, repeatEnabled: false, canShuffle: true, canRepeat: true)))
        #expect(snapshot.group(gid)?.progress.durationMillis == 246000)
        #expect(snapshot.group(gid)?.progress.positionMillis == 140000)
    }

    @Test func topologyKeepsProgressAndSetsSoftwareVersion() throws {
        var snapshot = SnapshotReducer.reduce(HouseholdSnapshot(), try topology())
        #expect(snapshot.softwareVersion == "96.1-79270")
        snapshot = SnapshotReducer.reduce(snapshot, .metadata(groupID: gid, nowPlaying: nil, durationMillis: 5000))
        snapshot = SnapshotReducer.reduce(snapshot, try topology())
        #expect(snapshot.group(gid)?.progress.durationMillis == 5000)
    }
```

In `HouseholdTests.swift`, inside `socketEventsUpdateTheSnapshot` after the existing assertions and before `stop()`, add:
```swift
        socket.push(#"[{"namespace":"playback:1","type":"playbackStatus","groupId":"\#(gid)"},{"playbackState":"PLAYBACK_STATE_PLAYING","positionMillis":5000,"playModes":{"shuffle":true,"repeat":false},"availablePlaybackActions":{"canShuffle":true,"canRepeat":false}}]"#)
        try await waitUntil { await h.household.current.group(gid)?.progress.shuffle == true }
        #expect(await h.household.current.group(gid)?.progress.canRepeat == false)
        #expect(await h.household.current.group(gid)?.progress.reportedAt == Date(timeIntervalSince1970: 42))
```
and make the `Harness` init pass a fixed clock: add `configuration.now = { Date(timeIntervalSince1970: 42) }` next to the existing `configuration.discoveryTimeout`/`backoff` lines.

- [ ] **Step 2: Run the tests to verify they fail**

```bash
swift test --filter "ModelsTests|SocketFrameTests|ReducerTests" 2>&1 | grep -E "error:" | head -5
```
Expected: compile errors about `PlaybackProgress`, `kind`, the new enum case shapes.

- [ ] **Step 3: Models and wire types**

In `Models.swift`, add after `NowPlaying`:
```swift
/// Where playback is within the current item, plus play modes. Position is a point-in-time
/// report; the app extrapolates from `reportedAt` while playing.
public struct PlaybackProgress: Hashable, Sendable {
    public var positionMillis: Int
    public var durationMillis: Int?
    public var reportedAt: Date
    public var shuffle: Bool
    public var repeatEnabled: Bool
    public var canShuffle: Bool
    public var canRepeat: Bool

    public init(positionMillis: Int, durationMillis: Int?, reportedAt: Date, shuffle: Bool, repeatEnabled: Bool, canShuffle: Bool, canRepeat: Bool) {
        self.positionMillis = positionMillis
        self.durationMillis = durationMillis
        self.reportedAt = reportedAt
        self.shuffle = shuffle
        self.repeatEnabled = repeatEnabled
        self.canShuffle = canShuffle
        self.canRepeat = canRepeat
    }

    public static let none = PlaybackProgress(positionMillis: 0, durationMillis: nil, reportedAt: .distantPast, shuffle: false, repeatEnabled: false, canShuffle: false, canRepeat: false)
}
```
In `Group`, add `public var progress: PlaybackProgress` and extend the init with a trailing `progress: PlaybackProgress = .none` parameter (keeps every existing call site compiling).

In `Favorite`, add:
```swift
    public enum Kind: String, Hashable, Sendable {
        case station, playlist, album, other

        public init(resourceType: String?) {
            switch resourceType {
            case "STREAM": self = .station
            case "PLAYLIST": self = .playlist
            case "ALBUM": self = .album
            default: self = .other
            }
        }
    }
    public var kind: Kind
```
and extend `Favorite.init` with a trailing `kind: Kind = .other` parameter after `serviceName` (existing call sites keep compiling; tests call `Favorite(id:name:subtitle:serviceName:kind:)`).
and extend its init with a trailing `kind: Kind = .other`.

In `HouseholdSnapshot.swift`, add `public var softwareVersion: String?` with a trailing init parameter `softwareVersion: String? = nil`.

In `WireTypes.swift`:
```swift
struct WirePlayModes: Decodable, Sendable {
    var shuffle: Bool?
    var `repeat`: Bool?
}

struct WirePlaybackActions: Decodable, Sendable {
    var canShuffle: Bool?
    var canRepeat: Bool?
}

struct WirePlaybackStatus: Decodable, Sendable {
    var playbackState: String
    var positionMillis: Int?
    var playModes: WirePlayModes?
    var availablePlaybackActions: WirePlaybackActions?
}
```
Add `var durationMillis: Int?` to `WireTrack`; add `var resource: WireResource?` to `WireFavorite` with `struct WireResource: Decodable, Sendable { var type: String? }`; add `var softwareVersion: String?` to `WirePlayer`.

In `WireMapping.swift`, add to `PlaybackProgress`:
```swift
extension PlaybackProgress {
    /// Builds a report from a playbackStatus body; duration is unknown here (it comes from metadata).
    init(wire: WirePlaybackStatus, reportedAt: Date) {
        self.init(
            positionMillis: wire.positionMillis ?? 0,
            durationMillis: nil,
            reportedAt: reportedAt,
            shuffle: wire.playModes?.shuffle ?? false,
            repeatEnabled: wire.playModes?.repeat ?? false,
            canShuffle: wire.availablePlaybackActions?.canShuffle ?? false,
            canRepeat: wire.availablePlaybackActions?.canRepeat ?? false
        )
    }
}
```
and in `Favorite.init(wire:)` pass `kind: Kind(resourceType: wire.resource?.type)`.

- [ ] **Step 4: Events and reducer**

`SocketEvent` cases become `playbackStatus(groupID: String, state: PlaybackState, progress: PlaybackProgress)` and `metadata(groupID: String, nowPlaying: NowPlaying?, durationMillis: Int?)`. `SocketFrameDecoder.decode` gains a parameter `now: Date = Date()` and builds `PlaybackProgress(wire: frame.body, reportedAt: now)`; for metadata it passes `frame.body.currentItem?.track?.durationMillis`.

`HouseholdEvent` cases likewise: `playbackStatus(groupID:state:progress:)`, `metadata(groupID:nowPlaying:durationMillis:)`.

`SnapshotReducer`:
```swift
        case .playbackStatus(let groupID, let state, let progress):
            update(&next, groupID) { group in
                group.playbackState = state
                let duration = group.progress.durationMillis
                group.progress = progress
                group.progress.durationMillis = duration
            }

        case .metadata(let groupID, let nowPlaying, let durationMillis):
            update(&next, groupID) { group in
                group.nowPlaying = nowPlaying
                group.progress.durationMillis = durationMillis
            }
```
In the `.topology` case, preserve `progress: old?.progress ?? .none` when rebuilding each `Group`, and set `next.softwareVersion = wirePlayers.first?.softwareVersion ?? snapshot.softwareVersion`.

`Household`: add `public var now: @Sendable () -> Date = { Date() }` to `Configuration`; in `handle(socketOutput:)` map `.playbackStatus(let g, let s, let p)` to `apply(.playbackStatus(groupID: g, state: s, progress: p))` and `.metadata(let g, let n, let d)` to `apply(.metadata(groupID: g, nowPlaying: n, durationMillis: d))`. Where `PlayerSocket` decodes frames (`PlayerSocket.run`, the `SocketFrameDecoder.decode(data)` call), pass `now: configuration.now()` by giving `PlayerSocket` a `now: @Sendable () -> Date` init parameter (default `{ Date() }`) that `Household.ensureSockets` fills from `configuration.now`.

- [ ] **Step 5: Run the tests to verify they pass**

```bash
swift test 2>&1 | grep -E "Test run with|failed" | tail -3
```
Expected: `Test run with 78 tests … passed` (71 + 2 models + 2 socket + 2 reducer + the extended household test counts as 0 new). Fix any test that still pattern-matches the old two-element cases (grep for `.playbackStatus(groupID:` and `.metadata(groupID:` across `Tests/`).

- [ ] **Step 6: Commit**

```bash
git add Packages/SonosKit
git commit -m "feat(sonoskit): expose playback progress, play modes, favorite kind and software version"
```

---

### Task 2: Play-mode command

**Files:**
- Modify: `Packages/SonosKit/Sources/SonosKit/LocalAPI/LocalAPIClient.swift`
- Modify: `Packages/SonosKit/Sources/SonosKit/Household/Household.swift`
- Test: `Packages/SonosKit/Tests/SonosKitTests/LocalAPIClientTests.swift`, `HouseholdTests.swift`

**Interfaces:**
- Produces: `LocalAPIClient.setPlayModes(shuffle: Bool, repeat: Bool, groupID: String, at address: String) async throws` posting `{"playModes":{"shuffle":…,"repeat":…}}` to `/groups/{gid}/playback/playMode`; `Household.setShuffle(_ on: Bool, group: String)` and `Household.setRepeat(_ on: Bool, group: String)`, each sending the full pair with the other value taken from the current snapshot.

- [ ] **Step 1: Write the failing tests**

Append to `LocalAPIClientTests.swift`:
```swift
    @Test func setPlayModesPostsBothFlags() async throws {
        try await client.setPlayModes(shuffle: true, repeat: false, groupID: gid, at: "192.168.1.216")
        let request = try #require(transport.requests.first)
        #expect(request.url.path() == "/api/v1/groups/\(gid)/playback/playMode")
        let body = try #require(try JSONSerialization.jsonObject(with: #require(request.body)) as? [String: Any])
        let modes = try #require(body["playModes"] as? [String: Any])
        #expect(modes["shuffle"] as? Bool == true)
        #expect(modes["repeat"] as? Bool == false)
    }
```
(if `url.path()` is rejected use `url.path`, as the file already does.)

Append to `HouseholdTests.swift`:
```swift
    @Test func shuffleAndRepeatSendTheFullPairToTheCoordinator() async throws {
        let h = Harness()
        _ = try await h.startAndDiscover(stereo)
        try await waitUntil { h.transport.socket(forHost: "192.168.1.216") != nil }
        let socket = try #require(h.transport.socket(forHost: "192.168.1.216"))
        socket.push(#"[{"namespace":"playback:1","type":"playbackStatus","groupId":"\#(gid)"},{"playbackState":"PLAYBACK_STATE_PLAYING","positionMillis":0,"playModes":{"shuffle":false,"repeat":true},"availablePlaybackActions":{"canShuffle":true,"canRepeat":true}}]"#)
        try await waitUntil { await h.household.current.group(gid)?.progress.repeatEnabled == true }
        try await h.household.setShuffle(true, group: gid)
        let request = try #require(h.transport.requests(matching: "/playback/playMode").last)
        #expect(request.url.host() == "192.168.1.216")
        let body = try #require(try JSONSerialization.jsonObject(with: #require(request.body)) as? [String: Any])
        let modes = try #require(body["playModes"] as? [String: Any])
        #expect(modes["shuffle"] as? Bool == true)
        #expect(modes["repeat"] as? Bool == true)
        await h.household.stop()
    }
```

- [ ] **Step 2: Run to verify failure, then implement**

```bash
swift test --filter "LocalAPIClientTests|HouseholdTests" 2>&1 | grep -E "error:" | head -3
```

`LocalAPIClient.swift`, in the group commands section:
```swift
    public func setPlayModes(shuffle: Bool, repeat: Bool, groupID: String, at address: String) async throws {
        try await post(address: address, path: "/groups/\(groupID)/playback/playMode", body: PlayModeBody(playModes: .init(shuffle: shuffle, repeat: `repeat`)))
    }
```
with, next to the other bodies:
```swift
    private struct PlayModeBody: Encodable {
        struct Modes: Encodable { var shuffle: Bool; var `repeat`: Bool }
        var playModes: Modes
    }
```

`Household.swift`, next to `play/pause`:
```swift
    public func setShuffle(_ on: Bool, group id: String) async throws {
        let current = snapshot.group(id)?.progress ?? .none
        try await groupCommand(id) { try await api.setPlayModes(shuffle: on, repeat: current.repeatEnabled, groupID: id, at: $0) }
    }

    public func setRepeat(_ on: Bool, group id: String) async throws {
        let current = snapshot.group(id)?.progress ?? .none
        try await groupCommand(id) { try await api.setPlayModes(shuffle: current.shuffle, repeat: on, groupID: id, at: $0) }
    }
```

- [ ] **Step 3: Run the tests to verify they pass**

```bash
swift test 2>&1 | grep -E "Test run with|failed" | tail -2
```
Expected: 80 tests pass.

- [ ] **Step 4: Commit**

```bash
git add Packages/SonosKit
git commit -m "feat(sonoskit): add shuffle and repeat commands"
```

---
### Task 3: App state for the new model (pure logic first)

**Files:**
- Create: `SonosRemote/App/Screen.swift`
- Create: `SonosRemote/App/PlaybackDisplay.swift`
- Create: `SonosRemote/App/TonePreset.swift`
- Create: `SonosRemote/App/FavoritesFilter.swift`
- Rename: `SonosRemote/App/RowOpenPolicy.swift` → `SonosRemote/App/SelectionPolicy.swift` (`git mv`), type renamed `SelectionPolicy`
- Modify: `SonosRemote/App/AppState.swift`
- Rename: `SonosRemoteTests/RowOpenPolicyTests.swift` → `SonosRemoteTests/SelectionPolicyTests.swift`
- Create: `SonosRemoteTests/PlaybackDisplayTests.swift`, `TonePresetTests.swift`, `FavoritesFilterTests.swift`
- Modify: `SonosRemoteTests/AppStateTests.swift`

**Interfaces:**
- Consumes: Task 1–2 types (`PlaybackProgress`, `Favorite.kind`, `Household.setShuffle/setRepeat`).
- Produces: everything listed under "App (Task 3)" in the interfaces block at the top. `AppState.openGroupID`, `toggleRow`, `selectedTab`, `OpenRowTab`, `rowErrors` keyed changes: `rowErrors` stays as is; `openGroupID`/`toggleRow`/`selectedTab`/`OpenRowTab` are removed. Views from Task 4 onward compile only against the new API; Task 4 deletes the old views, so this task will leave the app target temporarily not compiling — that is expected and the app tests are run at the end of Task 4. The package tests and the new pure tests still run here via `xcodebuild test -only-testing` after Task 4; in this task verify with `swift build`-free reasoning plus the `xcodebuild build` of the test target being deferred. To keep a green gate in this task, the old views are edited minimally to compile (see Step 4).

- [ ] **Step 1: Write the failing tests**

`SonosRemoteTests/SelectionPolicyTests.swift` (rename the existing file with `git mv`, then replace `RowOpenPolicy` with `SelectionPolicy` in it; the four tests keep their bodies).

`SonosRemoteTests/PlaybackDisplayTests.swift`:
```swift
import Foundation
import Testing
import SonosKit
@testable import SonosRemote

@Suite struct PlaybackDisplayTests {
    let t0 = Date(timeIntervalSince1970: 1_000)

    func progress(position: Int, duration: Int? = 246_000) -> PlaybackProgress {
        PlaybackProgress(positionMillis: position, durationMillis: duration, reportedAt: t0, shuffle: false, repeatEnabled: false, canShuffle: true, canRepeat: true)
    }

    @Test func playingExtrapolatesFromReportTime() {
        let shown = PlaybackDisplay.displayedPosition(progress: progress(position: 100_000), state: .playing, now: t0.addingTimeInterval(2.5))
        #expect(shown == 102_500)
    }

    @Test func playingClampsToDuration() {
        let shown = PlaybackDisplay.displayedPosition(progress: progress(position: 245_000), state: .playing, now: t0.addingTimeInterval(10))
        #expect(shown == 246_000)
    }

    @Test func pausedFreezes() {
        let shown = PlaybackDisplay.displayedPosition(progress: progress(position: 100_000), state: .paused, now: t0.addingTimeInterval(30))
        #expect(shown == 100_000)
    }

    @Test func unknownDurationYieldsNil() {
        #expect(PlaybackDisplay.displayedPosition(progress: progress(position: 100_000, duration: nil), state: .playing, now: t0) == nil)
    }

    @Test func formatsTimes() {
        #expect(PlaybackDisplay.timeString(millis: 102_500) == "1:42")
        #expect(PlaybackDisplay.timeString(millis: 0) == "0:00")
        #expect(PlaybackDisplay.timeString(millis: 3_725_000) == "62:05")
        #expect(PlaybackDisplay.remainingString(position: 102_500, duration: 290_000) == "−3:08")
        #expect(PlaybackDisplay.remainingString(position: 300_000, duration: 290_000) == "−0:00")
    }
}
```

`SonosRemoteTests/TonePresetTests.swift`:
```swift
import Testing
import SonosKit
@testable import SonosRemote

@Suite struct TonePresetTests {
    @Test func presetsHaveTheSpecifiedValues() {
        #expect(TonePreset.all.map(\.name) == ["Flat", "Warm", "Bright"])
        #expect(TonePreset.flat.bass == 0 && TonePreset.flat.treble == 0)
        #expect(TonePreset.warm.bass == 3 && TonePreset.warm.treble == -2)
        #expect(TonePreset.bright.bass == -2 && TonePreset.bright.treble == 3)
    }

    @Test func matchingIgnoresLoudnessAndSub() {
        #expect(TonePreset.matching(EQSettings(bass: 3, treble: -2, loudness: true, subGain: -5)) == .warm)
        #expect(TonePreset.matching(EQSettings(bass: 0, treble: 0, loudness: false, subGain: nil)) == .flat)
        #expect(TonePreset.matching(EQSettings(bass: 1, treble: 0, loudness: false, subGain: nil)) == nil)
    }

    @Test func applyingKeepsLoudnessAndSub() {
        let applied = TonePreset.bright.applied(to: EQSettings(bass: 0, treble: 0, loudness: true, subGain: -4))
        #expect(applied == EQSettings(bass: -2, treble: 3, loudness: true, subGain: -4))
    }
}
```

`SonosRemoteTests/FavoritesFilterTests.swift`:
```swift
import Testing
import SonosKit
@testable import SonosRemote

@Suite struct FavoritesFilterTests {
    let favorites = [
        Favorite(id: "1", name: "P3", subtitle: "Sveriges Radio", serviceName: "Sveriges Radio", kind: .station),
        Favorite(id: "2", name: "Late Night Tapes", subtitle: "Playlist · 48 tracks", kind: .playlist),
        Favorite(id: "3", name: "Kitchen Jazz", subtitle: nil, serviceName: "Spotify", kind: .playlist),
    ]

    @Test func emptyQueryReturnsEverything() {
        #expect(FavoritesFilter.apply(favorites, query: "   ").map(\.id) == ["1", "2", "3"])
    }

    @Test func matchesNameSubtitleAndServiceCaseInsensitively() {
        #expect(FavoritesFilter.apply(favorites, query: "sveriges").map(\.id) == ["1"])
        #expect(FavoritesFilter.apply(favorites, query: "TAPES").map(\.id) == ["2"])
        #expect(FavoritesFilter.apply(favorites, query: "spotify").map(\.id) == ["3"])
        #expect(FavoritesFilter.apply(favorites, query: "zzz").isEmpty)
    }
}
```

Update `SonosRemoteTests/AppStateTests.swift`: replace every `openGroupID` with `selectedGroupID` and every `toggleRow(` with `select(`; delete `userClosedRowStaysClosedWithoutTopologyChange` and `userClosedRowReopensOnTopologyChange` (there is no closed state any more) and replace them with:
```swift
    @Test func selectingAnotherGroupChangesTheSelection() {
        let appState = makeAppState()
        appState.apply(snapshot([group("a", .idle), group("b", .playing)]))
        appState.select("a")
        #expect(appState.selectedGroupID == "a")
        appState.apply(snapshot([group("a", .idle), group("b", .playing)]))
        #expect(appState.selectedGroupID == "a")
    }

    @Test func screensSwitchAndBackReturnsToMain() {
        let appState = makeAppState()
        #expect(appState.screen == .main)
        appState.show(.sound)
        #expect(appState.screen == .sound)
        appState.show(.sound)
        #expect(appState.screen == .main, "tapping the active screen's icon returns to main")
        appState.show(.favorites)
        appState.back()
        #expect(appState.screen == .main)
    }

    @Test func openingFavoritesTargetsTheSelectedRoomAndSoundTargetsItsCoordinator() {
        let appState = makeAppState()
        appState.apply(snapshot([Group(id: "g", name: "g", coordinatorID: "p1", playerIDs: ["p1", "p2"], playbackState: .playing, volume: .silent, nowPlaying: nil)]))
        appState.show(.favorites)
        #expect(appState.favoritesTargetGroupID == "g")
        appState.show(.sound)
        #expect(appState.soundPlayerID == "p1")
    }

    @Test func tickRunsOnlyWhilePresentedAndPlaying() async throws {
        let appState = makeAppState(tickInterval: .milliseconds(20))
        appState.apply(snapshot([group("a", .playing)]))
        appState.setPanelPresented(true)
        try await Task.sleep(for: .milliseconds(120))
        #expect(appState.tick >= 3)
        appState.setPanelPresented(false)
        let frozen = appState.tick
        try await Task.sleep(for: .milliseconds(80))
        #expect(appState.tick == frozen)
    }
```
and give `makeAppState` a `tickInterval: Duration = .seconds(1)` parameter passed to `AppState.init`.

- [ ] **Step 2: Write the pure types**

`SonosRemote/App/Screen.swift`:
```swift
import Foundation

enum Screen: Hashable, CaseIterable {
    case main, favorites, sound, group, settings

    /// Uppercase header title; `main` uses the wordmark label instead.
    var title: String {
        switch self {
        case .main: "SONOS"
        case .favorites: "FAVORITES"
        case .sound: "SOUND"
        case .group: "GROUP"
        case .settings: "SETTINGS"
        }
    }

    var accessibilityName: String {
        switch self {
        case .main: "Main"
        case .favorites: "Favorites"
        case .sound: "Sound"
        case .group: "Group"
        case .settings: "Settings"
        }
    }

    /// The header icons, in order. `group` is reached from the rooms header, not the icons.
    static let iconScreens: [Screen] = [.favorites, .sound, .settings]

    var systemImage: String {
        switch self {
        case .main: "hifispeaker.2"
        case .favorites: "heart"
        case .sound: "slider.horizontal.3"
        case .group: "link"
        case .settings: "gearshape"
        }
    }
}
```

`SonosRemote/App/PlaybackDisplay.swift`:
```swift
import Foundation
import SonosKit

/// Pure helpers for the progress bar. Extrapolates from the last speaker report while playing.
enum PlaybackDisplay {
    static func displayedPosition(progress: PlaybackProgress, state: PlaybackState, now: Date) -> Int? {
        guard let duration = progress.durationMillis, duration > 0 else { return nil }
        var position = progress.positionMillis
        if state == .playing {
            let elapsed = now.timeIntervalSince(progress.reportedAt)
            if elapsed > 0 { position += Int(elapsed * 1000) }
        }
        return max(0, min(position, duration))
    }

    static func timeString(millis: Int) -> String {
        let totalSeconds = max(0, millis / 1000)
        return "\(totalSeconds / 60):" + String(format: "%02d", totalSeconds % 60)
    }

    /// Remaining time with a real minus sign, never below −0:00.
    static func remainingString(position: Int, duration: Int) -> String {
        "−" + timeString(millis: max(0, duration - position))
    }
}
```

`SonosRemote/App/TonePreset.swift`:
```swift
import Foundation
import SonosKit

struct TonePreset: Hashable, Identifiable {
    let id: String
    let name: String
    let bass: Int
    let treble: Int

    static let flat = TonePreset(id: "flat", name: "Flat", bass: 0, treble: 0)
    static let warm = TonePreset(id: "warm", name: "Warm", bass: 3, treble: -2)
    static let bright = TonePreset(id: "bright", name: "Bright", bass: -2, treble: 3)
    static let all = [flat, warm, bright]

    /// The preset whose bass and treble equal the settings, ignoring loudness and sub.
    static func matching(_ eq: EQSettings) -> TonePreset? {
        all.first { $0.bass == eq.bass && $0.treble == eq.treble }
    }

    func applied(to eq: EQSettings) -> EQSettings {
        var next = eq
        next.bass = bass
        next.treble = treble
        return next
    }
}
```

`SonosRemote/App/FavoritesFilter.swift`:
```swift
import Foundation
import SonosKit

enum FavoritesFilter {
    static func apply(_ favorites: [Favorite], query: String) -> [Favorite] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return favorites }
        return favorites.filter { favorite in
            [favorite.name, favorite.subtitle ?? "", favorite.serviceName ?? ""]
                .contains { $0.lowercased().contains(needle) }
        }
    }
}
```

`SonosRemote/App/SelectionPolicy.swift` (after `git mv`): rename the enum to `SelectionPolicy`; body unchanged.

- [ ] **Step 3: Rework AppState**

Replace the whole of `SonosRemote/App/AppState.swift` with:
```swift
import Foundation
import Observation
import SonosKit

extension PlaybackState {
    /// Playing or about to play; these groups sort to the top of the panel.
    var isActive: Bool { self == .playing || self == .buffering }
}

@MainActor @Observable
final class AppState {
    private(set) var snapshot = HouseholdSnapshot()

    /// Groups for display: the ones playing (or about to) first, then the rest, each tier by name.
    var orderedGroups: [Group] {
        snapshot.groups.sorted { lhs, rhs in
            let lhsActive = lhs.playbackState.isActive
            let rhsActive = rhs.playbackState.isActive
            if lhsActive != rhsActive { return lhsActive }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    /// The one room every screen shows. Never nil while groups exist.
    var selectedGroupID: String? {
        didSet { defaults.set(selectedGroupID, forKey: Self.selectedGroupKey) }
    }
    var selectedGroup: Group? { selectedGroupID.flatMap(snapshot.group) }

    // Navigation and per-screen state.
    private(set) var screen: Screen = .main
    var favoritesSearch = ""
    var favoritesTargetGroupID: String?
    var soundPlayerID: String?
    var eqByPlayer: [String: EQSettings] = [:]
    var rowErrors: [String: String] = [:]

    /// Increments once per second while the panel is visible and the selected group is playing;
    /// views read it so the progress bar re-renders between speaker reports.
    private(set) var tick = 0

    private(set) var household: Household
    private let defaults: UserDefaults
    private let clearDelay: Duration
    private let tickInterval: Duration
    private var consumeTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?
    private var panelPresented = false
    private var resolvedInitialSelection = false
    private var lastGroupIDs: Set<String> = []
    private var errorGeneration: [String: Int] = [:]
    private static let selectedGroupKey = "selectedGroupID"

    init(household: Household, defaults: UserDefaults = .standard, clearDelay: Duration = .seconds(3), tickInterval: Duration = .seconds(1)) {
        self.household = household
        self.defaults = defaults
        self.clearDelay = clearDelay
        self.tickInterval = tickInterval
        self.selectedGroupID = defaults.string(forKey: Self.selectedGroupKey)
    }

    static func live() -> AppState {
        let transport = URLSessionTransport()
        let household = Household(discovery: BonjourDiscovery(), transport: transport, trustStore: transport.trustStore)
        return AppState(household: household)
    }

    // MARK: Lifecycle

    func start() {
        guard consumeTask == nil else { return }
        consumeTask = Task { [household] in
            await household.start()
            for await snapshot in await household.snapshots() {
                self.apply(snapshot)
            }
        }
    }

    /// Tears the household down and starts discovery again (Settings → refresh, "No Sonos found" → Retry).
    func retryDiscovery() {
        consumeTask?.cancel()
        consumeTask = nil
        resolvedInitialSelection = false
        let old = household
        Task { await old.stop() }
        let transport = URLSessionTransport()
        household = Household(discovery: BonjourDiscovery(), transport: transport, trustStore: transport.trustStore)
        snapshot = HouseholdSnapshot()
        start()
    }

    func apply(_ snapshot: HouseholdSnapshot) {
        self.snapshot = snapshot
        guard !snapshot.groups.isEmpty else { return }
        let groupIDs = Set(snapshot.groups.map(\.id))
        let topologyChanged = groupIDs != lastGroupIDs
        let stillExists = selectedGroupID.map { id in snapshot.groups.contains { $0.id == id } } ?? false
        if !stillExists || !resolvedInitialSelection || (topologyChanged && selectedGroupID == nil) {
            selectedGroupID = SelectionPolicy.resolve(remembered: selectedGroupID, groups: snapshot.groups)
        }
        resolvedInitialSelection = true
        lastGroupIDs = groupIDs
        if let group = selectedGroup, !group.playerIDs.contains(soundPlayerID ?? "") {
            soundPlayerID = group.coordinatorID
        }
        updateTicking()
    }

    // MARK: Selection and navigation

    func select(_ groupID: String) {
        guard snapshot.group(groupID) != nil else { return }
        selectedGroupID = groupID
        soundPlayerID = snapshot.group(groupID)?.coordinatorID
        updateTicking()
    }

    /// Header icons: tapping the active screen's icon returns to main.
    func show(_ target: Screen) {
        let next: Screen = (target == screen) ? .main : target
        if next == .favorites { favoritesTargetGroupID = selectedGroupID; favoritesSearch = "" }
        if next == .sound { soundPlayerID = selectedGroup?.coordinatorID }
        screen = next
    }

    func back() { screen = .main }

    func setPanelPresented(_ presented: Bool) {
        panelPresented = presented
        updateTicking()
    }

    private func updateTicking() {
        let shouldTick = panelPresented && selectedGroup?.playbackState == .playing
        if shouldTick, tickTask == nil {
            tickTask = Task { [tickInterval] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: tickInterval)
                    if Task.isCancelled { break }
                    self.tick &+= 1
                }
            }
        } else if !shouldTick, let task = tickTask {
            task.cancel()
            tickTask = nil
        }
    }

    // MARK: Commands (fire and forget with inline error reporting)

    func togglePlayPause(group id: String) {
        guard let group = snapshot.group(id) else { return }
        if group.playbackState == .playing { pause(group: id) } else { play(group: id) }
    }

    func play(group id: String) { run(id) { try await self.household.play(group: id) } }
    func pause(group id: String) { run(id) { try await self.household.pause(group: id) } }
    func next(group id: String) { run(id) { try await self.household.next(group: id) } }
    func previous(group id: String) { run(id) { try await self.household.previous(group: id) } }
    func setShuffle(_ on: Bool, group id: String) { run(id) { try await self.household.setShuffle(on, group: id) } }
    func setRepeat(_ on: Bool, group id: String) { run(id) { try await self.household.setRepeat(on, group: id) } }

    func setGroupVolume(_ level: Int, group id: String) { run(id) { try await self.household.setGroupVolume(level, group: id) } }
    func setGroupMuted(_ muted: Bool, group id: String) { run(id) { try await self.household.setGroupMuted(muted, group: id) } }

    func setPlayerVolume(_ level: Int, player: String) {
        run(snapshot.group(containing: player)?.id ?? player) { try await self.household.setPlayerVolume(level, player: player) }
    }

    func setPlayerMuted(_ muted: Bool, player: String) {
        run(snapshot.group(containing: player)?.id ?? player) { try await self.household.setPlayerMuted(muted, player: player) }
    }

    func playFavorite(_ favoriteID: String, group id: String) { run(id) { try await self.household.playFavorite(favoriteID, group: id) } }

    func setMembership(of player: String, inGroup id: String, member: Bool) {
        guard let group = snapshot.group(id) else { return }
        var members = group.playerIDs
        if member, !members.contains(player) { members.append(player) }
        if !member { members.removeAll { $0 == player } }
        guard members != group.playerIDs, !members.isEmpty else { return }
        let newMembers = members
        run(id) { try await self.household.setGroupMembers(newMembers, group: id) }
    }

    func loadEQ(player: String) {
        Task {
            do { eqByPlayer[player] = try await household.eq(player: player) }
            catch { report(snapshot.group(containing: player)?.id ?? player, error) }
        }
    }

    func updateEQ(_ eq: EQSettings, player: String) {
        eqByPlayer[player] = eq
        run(snapshot.group(containing: player)?.id ?? player) { try await self.household.setEQ(eq, player: player) }
    }

    func applyPreset(_ preset: TonePreset, player: String) {
        guard let current = eqByPlayer[player] else { return }
        updateEQ(preset.applied(to: current), player: player)
    }

    func resetTone(player: String) {
        guard var eq = eqByPlayer[player] else { return }
        eq.bass = 0
        eq.treble = 0
        if eq.subGain != nil { eq.subGain = 0 }
        updateEQ(eq, player: player)
    }

    // MARK: Errors

    private func run(_ groupID: String, _ operation: @escaping @Sendable () async throws -> Void) {
        Task {
            do { try await operation() }
            catch { report(groupID, error) }
        }
    }

    func report(_ groupID: String, _ error: any Error) {
        let generation = (errorGeneration[groupID] ?? 0) + 1
        errorGeneration[groupID] = generation
        rowErrors[groupID] = Self.message(for: error)
        Task { [clearDelay] in
            try? await Task.sleep(for: clearDelay)
            if errorGeneration[groupID] == generation { rowErrors[groupID] = nil }
        }
    }

    static func message(for error: any Error) -> String {
        switch error {
        case let apiError as LocalAPIError:
            switch apiError {
            case .unauthorized, .invalidAPIKey: return "Not authorized. Check the Sonos app's connection security settings."
            case .groupGone, .coordinatorMoved: return "That group changed. Refreshing."
            case .http, .decoding: return "Couldn't reach the speaker."
            }
        case is HouseholdError:
            return "That room is no longer available."
        case is UPnPError:
            return "The speaker rejected the EQ change."
        default:
            return "Couldn't reach the speaker."
        }
    }
}
```
Keep the existing `report`/`message` bodies if they differ only cosmetically from the above; the behaviour (generation token, 3 s clear) must stay.

- [ ] **Step 4: Keep the old views compiling until Task 4 replaces them**

The old views reference `openGroupID`, `toggleRow`, `selectedTab`, `OpenRowTab`. Rather than patching them, delete them now together with their placeholders and replace `PanelView` with a one-screen stub so the target compiles: `git rm SonosRemote/Views/OpenRowView.swift SonosRemote/Views/ClosedRowView.swift SonosRemote/Views/GroupRowView.swift SonosRemote/Views/FavoritesTabView.swift SonosRemote/Views/EQTabView.swift SonosRemote/Views/GroupTabView.swift`, and replace `SonosRemote/Views/PanelView.swift` with:
```swift
import SwiftUI
import SonosKit

/// Temporary stub while the new shell is built (Task 4 replaces this file).
struct PanelView: View {
    @Environment(AppState.self) private var state
    let closePanel: () -> Void
    var openSettings: (OpenWindowAction) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Redesign in progress").font(.headline)
            Text(state.selectedGroup?.name ?? "No room").foregroundStyle(.secondary)
            StatusBannerView()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .padding(12)
        .frame(width: 420)
        .onExitCommand(perform: closePanel)
    }
}
```

- [ ] **Step 5: Run the app tests to verify they pass**

```bash
xcodegen generate >/dev/null && xcodebuild test -project SonosRemote.xcodeproj -scheme SonosRemote -destination 'platform=macOS' -derivedDataPath .build/xcode 2>&1 | grep -E "error:|Test run with|TEST (SUCCEEDED|FAILED)" | tail -3
```
Expected: 17 − 2 (removed) + 4 (AppState) + 5 (PlaybackDisplay) + 3 (TonePreset) + 2 (FavoritesFilter) = 29 tests pass. (`SelectionPolicyTests` keeps its four.) If `tickRunsOnlyWhilePresentedAndPlaying` is flaky, raise its sleeps but keep the ordering assertions.

- [ ] **Step 6: Commit**

```bash
git add -A SonosRemote SonosRemoteTests
git commit -m "feat(app): selection-based app state with screens, progress display, presets and favorites filter"
```

---
### Task 4: Shell, components, and app wiring

**Files:**
- Create: `SonosRemote/Views/Components/SectionLabel.swift`, `Card.swift`, `RoomPicker.swift`, `IconButton.swift`
- Create: `SonosRemote/Views/Shell/HeaderView.swift`, `PanelShellView.swift`
- Move: `SonosRemote/Views/FooterView.swift` → `SonosRemote/Views/Shell/FooterView.swift` (`git mv`), rewritten
- Create placeholders: `SonosRemote/Views/Main/MainScreen.swift`, `SonosRemote/Views/Favorites/FavoritesScreen.swift`, `SonosRemote/Views/Sound/SoundScreen.swift`, `SonosRemote/Views/Group/GroupScreen.swift`, `SonosRemote/Views/Settings/SettingsScreen.swift` (each a labelled stub replaced in Tasks 5–9)
- Delete: `SonosRemote/Views/PanelView.swift`, `SonosRemote/Views/SettingsView.swift`, `SonosRemote/App/SettingsOpener.swift`
- Modify: `SonosRemote/App/SonosRemoteApp.swift`, `SonosRemote/App/PanelController.swift`

**Interfaces:**
- Consumes: `AppState.screen/show/back/setPanelPresented/selectedGroup`, `Screen`, `Artwork(url:size:)`, `StatusBannerView`.
- Produces: `SectionLabel(_ title: String, trailing: () -> Trailing)` (+ a no-trailing init), `Card { content }` with `CardRow { content }` helper, `RoomPicker(title:selection:options:)` where options are `[(id: String, name: String)]`, `IconButton(systemImage:label:isActive:action:)`, `HeaderView()`, `FooterView()`, `PanelShellView(closePanel:)`; screen stubs `MainScreen()`, `FavoritesScreen()`, `SoundScreen()`, `GroupScreen()`, `SettingsScreen()`.

- [ ] **Step 1: Components**

`SonosRemote/Views/Components/SectionLabel.swift`:
```swift
import SwiftUI

/// Uppercase, letter-spaced section label with an optional trailing view (a link, a picker, a count).
struct SectionLabel<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    init(_ title: String, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }
}

extension SectionLabel where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title, trailing: { EmptyView() })
    }
}
```

`SonosRemote/Views/Components/Card.swift`:
```swift
import SwiftUI

/// Rounded surface used by every sub-screen. Put `CardRow`s inside; they draw their own separators.
struct Card<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) { content() }
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.horizontal, 16)
    }
}

/// One row inside a Card: 12 pt padding and a hairline above every row but the first.
struct CardRow<Content: View>: View {
    var isFirst = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            if !isFirst { Divider().padding(.leading, 12) }
            HStack(spacing: 12) { content() }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
    }
}
```

`SonosRemote/Views/Components/RoomPicker.swift`:
```swift
import SwiftUI

/// Menu-style picker showing a speaker glyph and the chosen name; used for "Play to" and "Tuning".
struct RoomPicker: View {
    let title: String
    @Binding var selection: String?
    let options: [(id: String, name: String)]

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(options, id: \.id) { option in
                Label(option.name, systemImage: "hifispeaker").tag(Optional(option.id))
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
        .accessibilityLabel(title)
    }
}
```

`SonosRemote/Views/Components/IconButton.swift`:
```swift
import SwiftUI

/// 28 pt header icon; shows a rounded background when it is the active screen.
struct IconButton: View {
    let systemImage: String
    let label: String
    var isActive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 28)
                .background(isActive ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}
```

- [ ] **Step 2: Header, footer, shell**

`SonosRemote/Views/Shell/HeaderView.swift`:
```swift
import SwiftUI
import SonosKit

struct HeaderView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        HStack(spacing: 8) {
            if state.screen == .main {
                Text(Screen.main.title)
                    .font(.system(size: 12, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(.secondary)
            } else {
                Button { state.back() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold)).frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                .keyboardShortcut("[", modifiers: .command)
                Artwork(url: state.selectedGroup?.nowPlaying?.artworkURL, size: 22)
                Text(state.screen.title)
                    .font(.system(size: 12, weight: .bold))
                    .tracking(1.6)
            }
            Spacer()
            ForEach(Screen.iconScreens, id: \.self) { screen in
                IconButton(systemImage: screen.systemImage, label: screen.accessibilityName, isActive: state.screen == screen) {
                    withAnimation(.easeInOut(duration: 0.2)) { state.show(screen) }
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .accessibilityElement(children: .contain)
    }
}
```

`SonosRemote/Views/Shell/FooterView.swift` (after `git mv`):
```swift
import SwiftUI

struct FooterView: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    var body: some View {
        HStack {
            Text("Remote for Sonos \(version)").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.callout)
                .foregroundStyle(.secondary)
                .keyboardShortcut("q")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
```

`SonosRemote/Views/Shell/PanelShellView.swift`:
```swift
import SwiftUI
import SonosKit

/// The whole panel: header, the current screen (sliding in and out), footer.
struct PanelShellView: View {
    @Environment(AppState.self) private var state
    @Environment(PanelController.self) private var panel
    let closePanel: () -> Void

    @State private var bodyHeight: CGFloat = 0
    private static let maximumBodyHeight: CGFloat = 640

    var body: some View {
        VStack(spacing: 0) {
            HeaderView()
            Divider()
            ScrollView {
                screenView
                    .frame(width: 420)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bodyHeight = $0 }
            }
            .frame(height: min(bodyHeight, Self.maximumBodyHeight))
            .clipped()
            Divider()
            FooterView()
        }
        .frame(width: 420)
        .onExitCommand(perform: closePanel)
        .onChange(of: panel.isPresented, initial: true) { _, presented in state.setPanelPresented(presented) }
    }

    @ViewBuilder private var screenView: some View {
        ZStack(alignment: .top) {
            switch state.screen {
            case .main: MainScreen().transition(.move(edge: .leading))
            case .favorites: FavoritesScreen().transition(.move(edge: .trailing))
            case .sound: SoundScreen().transition(.move(edge: .trailing))
            case .group: GroupScreen().transition(.move(edge: .trailing))
            case .settings: SettingsScreen().transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: state.screen)
    }
}
```

Screen stubs, one file each, all with this shape (replace `MainScreen`/"Main" per file):
```swift
import SwiftUI
import SonosKit

struct MainScreen: View {
    @Environment(AppState.self) private var state
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            StatusBannerView()
            Text("Main screen: replaced in Task 5").font(.caption).foregroundStyle(.secondary).padding(16)
        }
    }
}
```
(`FavoritesScreen` → Task 6, `SoundScreen` → Task 7, `GroupScreen` → Task 8, `SettingsScreen` → Task 9.)

- [ ] **Step 3: App wiring and deletions**

`git rm SonosRemote/Views/PanelView.swift SonosRemote/Views/SettingsView.swift SonosRemote/App/SettingsOpener.swift`.

`SonosRemote/App/SonosRemoteApp.swift`:
```swift
import SwiftUI
import SonosKit
import MenuBarExtraAccess
import KeyboardShortcuts

@main
struct SonosRemoteApp: App {
    @State private var appState: AppState
    @State private var panel: PanelController

    init() {
        let panel = PanelController()
        _panel = State(initialValue: panel)
        let appState = AppState.live()
        _appState = State(initialValue: appState)
        appState.start()
        KeyboardShortcuts.onKeyUp(for: .togglePanel) {
            Task { @MainActor in panel.toggle() }
        }
    }

    var body: some Scene {
        MenuBarExtra("Sonos", systemImage: "hifispeaker.2") {
            PanelShellView(closePanel: { panel.close() })
                .environment(appState)
                .environment(panel)
        }
        .menuBarExtraAccess(isPresented: $panel.isPresented)
        .menuBarExtraStyle(.window)
    }
}
```
`PanelController.swift` is unchanged (it already exposes `isPresented`, `toggle()`, `close()`).

- [ ] **Step 4: Build, test, run**

```bash
xcodegen generate >/dev/null
xcodebuild -project SonosRemote.xcodeproj -scheme SonosRemote -configuration Debug -derivedDataPath .build/xcode build 2>&1 | grep -E "error:|warning: .*SonosRemote/|BUILD" | head
xcodebuild test -project SonosRemote.xcodeproj -scheme SonosRemote -destination 'platform=macOS' -derivedDataPath .build/xcode 2>&1 | grep -E "error:|Test run with|TEST (SUCCEEDED|FAILED)" | tail -3
pkill -x SonosRemote; open .build/xcode/Build/Products/Debug/SonosRemote.app
```
Expected: `BUILD SUCCEEDED`, 29 tests pass. Owner check: the panel is 420 pt wide with the SONOS label and three icons; each icon slides in a stub screen with a back chevron and the room's thumbnail; tapping the active icon or the chevron returns; Escape closes; the footer shows the version and Quit.

- [ ] **Step 5: Commit**

```bash
git add -A SonosRemote
git commit -m "feat(app): new panel shell with header navigation, footer and screen stubs"
```

---
### Task 5: Main screen (hero, progress, transport, volume, rooms)

**Files:**
- Modify: `SonosRemote/Views/Artwork.swift` (add `placeholder`)
- Modify: `SonosRemote/Views/VolumeSliderView.swift` (replace `indent`/`compact` with a `style`)
- Modify: `SonosRemote/Views/StatusBannerView.swift` (card look)
- Modify: `SonosRemote/App/PlaybackDisplay.swift` (add `nowPlayingLine(for:)`, `sourceLine(for:)`)
- Create: `SonosRemote/Views/Components/ErrorLine.swift`
- Create: `SonosRemote/Views/Main/HeroView.swift`, `ProgressBarView.swift`, `VolumeRowView.swift`, `RoomsListView.swift`, `RoomRowView.swift`
- Move: `SonosRemote/Views/TransportView.swift` → `SonosRemote/Views/Main/TransportView.swift` (`git mv`), rewritten
- Replace: `SonosRemote/Views/Main/MainScreen.swift` (the Task 4 stub)
- Modify: `SonosRemoteTests/PlaybackDisplayTests.swift`

**Interfaces:**
- Consumes: `AppState.selectedGroup/selectedGroupID/orderedGroups/snapshot/rowErrors/tick/select(_:)/show(_:)/togglePlayPause(group:)/next(group:)/previous(group:)/setShuffle(_:group:)/setRepeat(_:group:)/setGroupVolume(_:group:)/setGroupMuted(_:group:)`, `PlaybackDisplay.displayedPosition/timeString/remainingString`, `Group.progress` (`PlaybackProgress.shuffle/repeatEnabled/canShuffle/canRepeat/durationMillis`), `NowPlaying.title/artist/album/artworkURL/serviceName/containerName`, `SectionLabel`, `SonosGroup`.
- Produces: `Artwork(url:size:placeholder:)` (placeholder defaults to `"music.note"`), `VolumeSliderView(label:volume:accessibilityName:style:onChange:onMute:)` with `VolumeSliderView.Style { labelled, compact, hero }`, `ErrorLine(text:)`, `PlaybackDisplay.nowPlayingLine(for:)`, `PlaybackDisplay.sourceLine(for:)`, `HeroView(group:)`, `ProgressBarView(group:)`, `TransportView(group:)`, `VolumeRowView(group:)`, `RoomsListView()`, `RoomRowView(group:isSelected:focus:)`, `MainScreen()`.

- [ ] **Step 1: Write the failing tests**

Append inside the suite in `SonosRemoteTests/PlaybackDisplayTests.swift`:
```swift
    @Test func nowPlayingLineUsesTitleContainerOrNotPlaying() {
        let now = NowPlaying(title: "Blue in Green", containerName: "P3")
        var group = Group(id: "g", name: "Kitchen", coordinatorID: "p", playerIDs: ["p"], playbackState: .playing, volume: .silent, nowPlaying: now, progress: progress(position: 0))
        #expect(PlaybackDisplay.nowPlayingLine(for: group) == "Blue in Green")
        group.progress = progress(position: 0, duration: nil)
        #expect(PlaybackDisplay.nowPlayingLine(for: group) == "P3", "radio shows the station (container) instead of the track")
        group.playbackState = .idle
        #expect(PlaybackDisplay.nowPlayingLine(for: group) == "Not playing")
    }

    @Test func sourceLineJoinsServiceAndContainer() {
        #expect(PlaybackDisplay.sourceLine(for: NowPlaying(title: "t", serviceName: "Spotify", containerName: "Soft Evening Mix")) == "Spotify · Soft Evening Mix")
        #expect(PlaybackDisplay.sourceLine(for: NowPlaying(title: "t", serviceName: "Spotify")) == "Spotify")
        #expect(PlaybackDisplay.sourceLine(for: NowPlaying(title: "t")) == nil)
    }
```

- [ ] **Step 2: Run them to verify they fail**

```bash
xcodebuild test -project SonosRemote.xcodeproj -scheme SonosRemote -destination 'platform=macOS' -derivedDataPath .build/xcode -only-testing:SonosRemoteTests/PlaybackDisplayTests 2>&1 | grep -E "error:|TEST (SUCCEEDED|FAILED)" | tail -3
```
Expected: compile errors, `nowPlayingLine` and `sourceLine` are not members of `PlaybackDisplay`.

- [ ] **Step 3: Pure helpers and shared pieces**

Append to `enum PlaybackDisplay` in `SonosRemote/App/PlaybackDisplay.swift`:
```swift
    /// Rooms list second line and the Group screen line: the track, the station for radio, or "Not playing".
    static func nowPlayingLine(for group: Group) -> String {
        guard group.playbackState != .idle, let now = group.nowPlaying else { return "Not playing" }
        if group.progress.durationMillis == nil, let container = now.containerName { return container }
        return now.title
    }

    /// "Spotify · Soft Evening Mix"; nil when the item names neither a service nor a container.
    static func sourceLine(for now: NowPlaying) -> String? {
        let parts = [now.serviceName, now.containerName].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
```

`SonosRemote/Views/Artwork.swift`:
```swift
import SwiftUI

struct Artwork: View {
    let url: URL?
    let size: CGFloat
    /// SF Symbol shown while there is no image: a note for tracks, a speaker for rooms, a radio for stations.
    var placeholder = "music.note"

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Rectangle().fill(.quaternary)
                    Image(systemName: placeholder).foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size > 48 ? 8 : 6, style: .continuous))
        .accessibilityHidden(true)
    }
}
```

`SonosRemote/Views/Components/ErrorLine.swift`:
```swift
import SwiftUI

/// One-line inline error under the control that failed; AppState clears it after a few seconds.
struct ErrorLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.red)
            .padding(.horizontal, 16)
            .padding(.top, 4)
    }
}
```

`SonosRemote/Views/VolumeSliderView.swift`: replace the declarations and `body` as below; keep `setLocalProgrammatically`, `commit`, `scheduleFlush` and every comment about the gate exactly as they are today.
```swift
import SwiftUI
import SonosKit

/// A 0–100 slider with a mute button. Sends through VolumeCommandGate so dragging
/// does not flood the speaker and incoming events do not fight the thumb.
struct VolumeSliderView: View {
    enum Style {
        /// Label, slider, readout, mute (kept for future per-room lists).
        case labelled
        /// Rooms list: slider and mute only.
        case compact
        /// Main screen volume row: mute glyph on the left, slider, readout.
        case hero
    }

    let label: String
    let volume: Volume
    let accessibilityName: String
    var style: Style = .labelled
    let onChange: (Int) -> Void
    let onMute: (Bool) -> Void

    @State private var local: Double = 0
    @State private var gate = VolumeCommandGate()
    @State private var flushTask: Task<Void, Never>?
    /// True while the user is actively dragging the slider (set by `onEditingChanged`).
    @State private var isUserEditing = false
    /// True while `local` is being written by us (onAppear / an accepted incoming update), so the
    /// resulting `onChange(of: local)` is not mistaken for a user edit and echoed back out.
    @State private var isProgrammaticUpdate = false

    var body: some View {
        HStack(spacing: 8) {
            if style == .hero { muteButton(glyph: "speaker.wave.1", size: 15) }
            if style == .labelled {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 78, alignment: .leading)
            }
            Slider(value: $local, in: 0...100, step: 1) { editing in
                isUserEditing = editing
                if !editing { commit() }
            }
            .disabled(volume.fixed)
            .accessibilityLabel("\(accessibilityName) volume")
            .accessibilityValue("\(Int(local)) percent\(volume.muted ? ", muted" : "")")
            .onChange(of: local) { _, newValue in
                // Only a genuine user edit (drag or, since keyboard arrow changes never call
                // onEditingChanged, a focused-slider arrow press) reaches here with the flag
                // clear; a write we made ourselves (onAppear, accepted incoming volume) always
                // sets the flag first, so this early return is what stops incoming updates from
                // being echoed straight back out as outgoing commands.
                guard !isProgrammaticUpdate else { return }
                if let send = gate.userChanged(to: Int(newValue), at: .now) { onChange(send) } else { scheduleFlush() }
            }
            if style != .compact {
                Text("\(Int(local))")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 28, alignment: .trailing)
                    .accessibilityHidden(true)
            }
            if style != .hero { muteButton(glyph: "speaker.wave.2.fill", size: 12) }
        }
        .onAppear { setLocalProgrammatically(Double(volume.level)) }
        .onChange(of: volume.level) { _, incoming in
            if !isUserEditing, gate.shouldAcceptIncoming(at: .now) { setLocalProgrammatically(Double(incoming)) }
        }
        .onDisappear { flushTask?.cancel() }
    }

    private func muteButton(glyph: String, size: CGFloat) -> some View {
        Button { onMute(!volume.muted) } label: {
            Image(systemName: volume.muted ? "speaker.slash.fill" : glyph)
                .font(.system(size: size))
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(volume.muted ? "Unmute \(accessibilityName)" : "Mute \(accessibilityName)")
    }

    // setLocalProgrammatically, commit, scheduleFlush: unchanged.
}
```

`SonosRemote/Views/StatusBannerView.swift` (card look; same states and copy):
```swift
import SwiftUI
import SonosKit

struct StatusBannerView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        switch state.snapshot.status {
        case .ready:
            EmptyView()
        case .discovering:
            Banner(color: .gray) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Looking for Sonos…").font(.callout).foregroundStyle(.secondary)
                }
            }
        case .noPlayersFound:
            Banner(color: .gray) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No Sonos found on this network").font(.callout.weight(.semibold))
                    Text("Your Mac must be on the same Wi‑Fi or wired network as the speakers.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Retry") { state.retryDiscovery() }.controlSize(.small)
                }
            }
        case .unauthorized:
            Banner(color: .yellow) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Authentication is switched on in the Sonos app").font(.callout.weight(.semibold))
                    Text("Turn it off under Settings → System → Network → Connection security so this app can control your speakers.").font(.caption)
                }
            }
        case .localNetworkDenied:
            Banner(color: .yellow) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Local Network access is off").font(.callout.weight(.semibold))
                    Text("Allow Remote for Sonos under System Settings → Privacy & Security → Local Network, then quit and reopen the app.").font(.caption)
                }
            }
        }
    }
}

/// The status card: a coloured dot, the content, the shared rounded background.
private struct Banner<Content: View>: View {
    let color: Color
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(color).frame(width: 8, height: 8).padding(.top, 5).accessibilityHidden(true)
            content()
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .accessibilityElement(children: .combine)
    }
}
```

- [ ] **Step 4: Main screen views**

`SonosRemote/Views/Main/HeroView.swift`:
```swift
import SwiftUI
import SonosKit

/// 96 pt artwork plus room, title, artist and album for the selected group.
struct HeroView: View {
    let group: SonosGroup?

    private var nowPlaying: NowPlaying? {
        guard let group, group.playbackState != .idle else { return nil }
        return group.nowPlaying
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Artwork(url: nowPlaying?.artworkURL, size: 96)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Image(systemName: "hifispeaker")
                    Text((group?.name ?? "No room selected").uppercased())
                }
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)
                if let now = nowPlaying {
                    Text(now.title).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                    if let artist = now.artist {
                        Text(artist).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    }
                    if let album = now.album ?? now.containerName {
                        Text(album).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                    }
                } else {
                    Text("Not playing").font(.system(size: 16, weight: .semibold)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 96)
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .accessibilityElement(children: .combine)
    }
}
```

`SonosRemote/Views/Main/ProgressBarView.swift`:
```swift
import SwiftUI
import SonosKit

/// 3 pt bar with elapsed, source and remaining; hidden (source only) when the duration is unknown.
struct ProgressBarView: View {
    @Environment(AppState.self) private var state
    let group: SonosGroup

    var body: some View {
        // Reading `tick` re-renders once a second while the room plays; the value itself is unused.
        let _ = state.tick
        let position = PlaybackDisplay.displayedPosition(progress: group.progress, state: group.playbackState, now: .now)
        let source = group.nowPlaying.flatMap(PlaybackDisplay.sourceLine(for:))
        VStack(spacing: 4) {
            if let position, let duration = group.progress.durationMillis {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary)
                        Capsule()
                            .fill(Color.primary.opacity(0.7))
                            .frame(width: geometry.size.width * CGFloat(position) / CGFloat(duration))
                    }
                }
                .frame(height: 3)
                .accessibilityElement()
                .accessibilityLabel("Progress")
                .accessibilityValue("\(PlaybackDisplay.timeString(millis: position)) of \(PlaybackDisplay.timeString(millis: duration))")
                HStack {
                    Text(PlaybackDisplay.timeString(millis: position)).accessibilityHidden(true)
                    Spacer()
                    if let source { Text(source).lineLimit(1) }
                    Spacer()
                    Text(PlaybackDisplay.remainingString(position: position, duration: duration)).accessibilityHidden(true)
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            } else if let source {
                Text(source)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }
}
```

`SonosRemote/Views/Main/TransportView.swift` (after `git mv`, full replacement):
```swift
import SwiftUI
import SonosKit

/// Shuffle, previous, play/pause (56 pt), next, repeat. Disabled as a whole when there is no group.
struct TransportView: View {
    @Environment(AppState.self) private var state
    let group: SonosGroup?

    var body: some View {
        let progress = group?.progress
        let isPlaying = group?.playbackState == .playing
        HStack(spacing: 22) {
            ToggleGlyph(systemImage: "shuffle", label: "Shuffle", isOn: progress?.shuffle ?? false, enabled: progress?.canShuffle ?? false) { on in
                if let group { state.setShuffle(on, group: group.id) }
            }
            Button { if let group { state.previous(group: group.id) } } label: {
                Image(systemName: "backward.end.fill").font(.system(size: 18))
            }
            .accessibilityLabel("Previous track")

            Button { if let group { state.togglePlayPause(group: group.id) } } label: {
                // Explicit colours: a hierarchical `.primary` fill would resolve against the
                // glyph's foreground style and paint the circle the same colour as the glyph.
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .windowBackgroundColor))
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(Color(nsColor: .labelColor)))
            }
            .accessibilityLabel(isPlaying ? "Pause" : "Play")

            Button { if let group { state.next(group: group.id) } } label: {
                Image(systemName: "forward.end.fill").font(.system(size: 18))
            }
            .accessibilityLabel("Next track")
            ToggleGlyph(systemImage: "repeat", label: "Repeat", isOn: progress?.repeatEnabled ?? false, enabled: progress?.canRepeat ?? false) { on in
                if let group { state.setRepeat(on, group: group.id) }
            }
        }
        .buttonStyle(.borderless)
        .disabled(group == nil)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}

/// Shuffle / repeat: accent colour when on, disabled when the speaker cannot do it.
private struct ToggleGlyph: View {
    let systemImage: String
    let label: String
    let isOn: Bool
    let enabled: Bool
    let action: (Bool) -> Void

    var body: some View {
        Button { action(!isOn) } label: {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                .frame(width: 28, height: 28)
        }
        .disabled(!enabled)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "on" : "off")
    }
}
```

`SonosRemote/Views/Main/VolumeRowView.swift`:
```swift
import SwiftUI
import SonosKit

struct VolumeRowView: View {
    @Environment(AppState.self) private var state
    let group: SonosGroup

    var body: some View {
        VolumeSliderView(
            label: "Volume",
            volume: group.volume,
            accessibilityName: group.name,
            style: .hero,
            onChange: { state.setGroupVolume($0, group: group.id) },
            onMute: { state.setGroupMuted($0, group: group.id) }
        )
        .padding(.horizontal, 16)
    }
}
```

`SonosRemote/Views/Main/RoomRowView.swift`:
```swift
import SwiftUI
import SonosKit

/// One group: art, name, now-playing line, compact slider. Art and text select; the slider does not.
struct RoomRowView: View {
    @Environment(AppState.self) private var state
    let group: SonosGroup
    let isSelected: Bool
    let focus: FocusState<String?>.Binding

    private var line: String { PlaybackDisplay.nowPlayingLine(for: group) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { state.select(group.id) } label: {
                    HStack(spacing: 12) {
                        Artwork(url: group.nowPlaying?.artworkURL, size: 40, placeholder: "hifispeaker")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.name).font(.callout.weight(.semibold)).lineLimit(1)
                            Text(line).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 8)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focused(focus, equals: group.id)
                .onKeyPress(.space) { state.togglePlayPause(group: group.id); return .handled }
                .onKeyPress(.return) { state.select(group.id); return .handled }
                .accessibilityLabel("\(group.name), \(line)")
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])

                VolumeSliderView(
                    label: group.name,
                    volume: group.volume,
                    accessibilityName: group.name,
                    style: .compact,
                    onChange: { state.setGroupVolume($0, group: group.id) },
                    onMute: { state.setGroupMuted($0, group: group.id) }
                )
                .frame(width: 130)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isSelected ? AnyShapeStyle(.quaternary.opacity(0.6)) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.horizontal, 8)
            if let error = state.rowErrors[group.id] { ErrorLine(text: error) }
        }
    }
}
```

`SonosRemote/Views/Main/RoomsListView.swift`:
```swift
import SwiftUI
import SonosKit

/// "ROOMS" with the Group link, then one row per group in AppState.orderedGroups. Up/Down move focus.
struct RoomsListView: View {
    @Environment(AppState.self) private var state
    @FocusState private var focusedGroupID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("ROOMS") {
                Button { state.show(.group) } label: {
                    Label("Group", systemImage: "link").font(.caption.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .disabled(state.selectedGroup == nil)
                .accessibilityLabel("Group rooms")
            }
            ForEach(state.orderedGroups) { group in
                RoomRowView(group: group, isSelected: group.id == state.selectedGroupID, focus: $focusedGroupID)
            }
        }
        .onMoveCommand { direction in
            let ids = state.orderedGroups.map(\.id)
            guard let current = focusedGroupID ?? state.selectedGroupID, let index = ids.firstIndex(of: current) else { return }
            switch direction {
            case .up where index > 0: focusedGroupID = ids[index - 1]
            case .down where index + 1 < ids.count: focusedGroupID = ids[index + 1]
            default: break
            }
        }
    }
}
```

`SonosRemote/Views/Main/MainScreen.swift` (replace the stub):
```swift
import SwiftUI
import SonosKit

struct MainScreen: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StatusBannerView()
            HeroView(group: state.selectedGroup)
            if let group = state.selectedGroup {
                ProgressBarView(group: group)
            }
            TransportView(group: state.selectedGroup)
            if let group = state.selectedGroup {
                VolumeRowView(group: group)
            }
            if !state.snapshot.groups.isEmpty {
                RoomsListView()
            }
        }
        .padding(.bottom, 12)
    }
}
```

- [ ] **Step 5: Build, test, run**

```bash
xcodegen generate >/dev/null && xcodebuild test -project SonosRemote.xcodeproj -scheme SonosRemote -destination 'platform=macOS' -derivedDataPath .build/xcode 2>&1 | grep -E "error:|Test run with|TEST (SUCCEEDED|FAILED)" | tail -3
pkill -x SonosRemote; open .build/xcode/Build/Products/Debug/SonosRemote.app
```
Expected: 31 tests pass (29 + 2). Owner check: the hero shows the playing room's art and text; the progress bar advances once a second and the remaining time counts down; radio shows only the source line; shuffle and repeat light up and toggle (and the Sonos app agrees); the volume row moves the group; clicking another row's text moves the hero to that room while its slider only changes its own volume; "Group" opens the GROUP screen; Up/Down/Return/Space work in the list.

- [ ] **Step 6: Commit**

```bash
git add -A SonosRemote SonosRemoteTests
git commit -m "feat(app): main screen with hero, progress bar, transport, volume and rooms list"
```

---
### Task 6: Favorites screen

**Files:**
- Create: `SonosRemote/Views/Components/SearchField.swift`
- Replace: `SonosRemote/Views/Favorites/FavoritesScreen.swift` (the Task 4 stub)
- Create: `SonosRemote/Views/Favorites/FavoriteRow.swift`
- Modify: `SonosRemoteTests/FavoritesFilterTests.swift`

**Interfaces:**
- Consumes: `AppState.favoritesSearch/favoritesTargetGroupID/selectedGroupID/orderedGroups/snapshot.favorites/rowErrors/playFavorite(_:group:)`, `FavoritesFilter.apply(_:query:)`, `Favorite.kind` (`Favorite.Kind`: `.station/.playlist/.album/.other`), `SectionLabel`, `Card`, `CardRow`, `RoomPicker`, `Artwork(url:size:placeholder:)` and `ErrorLine(text:)` from Task 5, `StatusBannerView`.
- Produces: `SearchField(text:prompt:)`, `Favorite.secondLine`, `Favorite.Kind.glyph`.

- [ ] **Step 1: Write the failing test**

Append to `SonosRemoteTests/FavoritesFilterTests.swift` inside the suite:
```swift
    @Test func secondLineJoinsSubtitleOrServiceWithKind() {
        #expect(favorites[0].secondLine == "Sveriges Radio · Station")
        #expect(favorites[1].secondLine == "Playlist · 48 tracks · Playlist")
        #expect(favorites[2].secondLine == "Spotify · Playlist")
        #expect(Favorite(id: "4", name: "Mix", subtitle: nil, kind: .other).secondLine == "")
    }
```

- [ ] **Step 2: Run it to verify it fails**

```bash
xcodegen generate >/dev/null && xcodebuild test -project SonosRemote.xcodeproj -scheme SonosRemote -destination 'platform=macOS' -derivedDataPath .build/xcode -only-testing:SonosRemoteTests/FavoritesFilterTests 2>&1 | grep -E "error:|TEST (SUCCEEDED|FAILED)" | tail -3
```
Expected: compile error, `secondLine` is not a member of `Favorite`.

- [ ] **Step 3: Write the views**

`SonosRemote/Views/Components/SearchField.swift`:
```swift
import SwiftUI

struct SearchField: View {
    @Binding var text: String
    let prompt: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .accessibilityLabel(prompt)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
```

`SonosRemote/Views/Favorites/FavoriteRow.swift`:
```swift
import SwiftUI
import SonosKit

/// One favorite: artwork or type glyph, name, second line, play. The whole row plays.
struct FavoriteRow: View {
    let favorite: Favorite
    let play: () -> Void

    var body: some View {
        Button(action: play) {
            HStack(spacing: 12) {
                Artwork(url: favorite.imageURL, size: 40, placeholder: favorite.kind.glyph)
                VStack(alignment: .leading, spacing: 2) {
                    Text(favorite.name).font(.callout.weight(.medium)).lineLimit(1)
                    if !favorite.secondLine.isEmpty {
                        Text(favorite.secondLine).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "play.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Play \(favorite.name)")
    }
}

extension Favorite.Kind {
    var glyph: String {
        switch self {
        case .station: "dot.radiowaves.left.and.right"
        case .playlist: "music.note.list"
        case .album: "opticaldisc"
        case .other: "music.note"
        }
    }

    var label: String? {
        switch self {
        case .station: "Station"
        case .playlist: "Playlist"
        case .album: "Album"
        case .other: nil
        }
    }
}

extension Favorite {
    /// "Sveriges Radio · Station": the subtitle (or the service when there is none) and the kind.
    var secondLine: String {
        [subtitle ?? serviceName, kind.label].compactMap { $0 }.joined(separator: " · ")
    }
}
```

`SonosRemote/Views/Favorites/FavoritesScreen.swift` (replace the stub):
```swift
import SwiftUI
import SonosKit

struct FavoritesScreen: View {
    @Environment(AppState.self) private var state

    private var filtered: [Favorite] { FavoritesFilter.apply(state.snapshot.favorites, query: state.favoritesSearch) }
    private var targetOptions: [(id: String, name: String)] { state.orderedGroups.map { ($0.id, $0.name) } }
    private var targetGroupID: String? { state.favoritesTargetGroupID ?? state.selectedGroupID }
    private var isSearching: Bool { !state.favoritesSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        @Bindable var state = state
        VStack(alignment: .leading, spacing: 0) {
            StatusBannerView()
            SectionLabel("PLAY TO") {
                RoomPicker(title: "Play to", selection: $state.favoritesTargetGroupID, options: targetOptions)
            }
            SearchField(text: $state.favoritesSearch, prompt: "Search favorites")
                .padding(.horizontal, 16)
            SectionLabel("ALL FAVORITES") {
                Text("\(filtered.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("\(filtered.count) favorites")
            }
            if filtered.isEmpty {
                Text(isSearching ? "No favorites match" : "No favorites in your Sonos system yet")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                Card {
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { index, favorite in
                        CardRow(isFirst: index == 0) {
                            FavoriteRow(favorite: favorite) { play(favorite) }
                        }
                    }
                }
            }
            if let targetGroupID, let error = state.rowErrors[targetGroupID] {
                ErrorLine(text: error)
            }
        }
        .padding(.bottom, 12)
    }

    private func play(_ favorite: Favorite) {
        guard let targetGroupID else { return }
        state.playFavorite(favorite.id, group: targetGroupID)
    }
}
```

- [ ] **Step 4: Build, test, run**

```bash
xcodebuild test -project SonosRemote.xcodeproj -scheme SonosRemote -destination 'platform=macOS' -derivedDataPath .build/xcode 2>&1 | grep -E "error:|Test run with|TEST (SUCCEEDED|FAILED)" | tail -3
pkill -x SonosRemote; open .build/xcode/Build/Products/Debug/SonosRemote.app
```
Expected: 32 tests pass (31 + `secondLineJoinsSubtitleOrServiceWithKind`). Owner check on the heart icon: the picker shows the selected room; typing filters the list and the count updates; clearing restores everything; a station shows the radio glyph when it has no image; clicking a row starts it on the chosen room.

- [ ] **Step 5: Commit**

```bash
git add -A SonosRemote SonosRemoteTests
git commit -m "feat(app): favorites screen with play-to picker, search and type glyphs"
```

---

### Task 7: Sound screen

**Files:**
- Replace: `SonosRemote/Views/Sound/SoundScreen.swift` (the Task 4 stub)
- Create: `SonosRemote/Views/Sound/PresetChips.swift`, `SonosRemote/Views/Sound/ToneSlider.swift`
- Modify: `SonosRemote/App/TonePreset.swift` (add `ToneValue`)
- Modify: `SonosRemoteTests/TonePresetTests.swift`

**Interfaces:**
- Consumes: `AppState.soundPlayerID/selectedGroup/snapshot.players/eqByPlayer/rowErrors/loadEQ(player:)/updateEQ(_:player:)/applyPreset(_:player:)/resetTone(player:)`, `TonePreset.all/matching(_:)`, `EQSettings` + `bassRange/trebleRange/subGainRange`, `Player.hasSub`, `SectionLabel`, `Card`, `CardRow`, `RoomPicker`, `ErrorLine`, `StatusBannerView`.
- Produces: `ToneValue.string(_:)`, `PresetChips(current:onSelect:)`, `ToneSlider(label:value:range:room:onChange:)`.

- [ ] **Step 1: Write the failing test**

Append to `SonosRemoteTests/TonePresetTests.swift` inside the suite:
```swift
    @Test func toneValuesUseSignsAndARealMinus() {
        #expect(ToneValue.string(3) == "+3")
        #expect(ToneValue.string(-2) == "−2")
        #expect(ToneValue.string(0) == "0")
    }
```

- [ ] **Step 2: Run it to verify it fails**

```bash
xcodebuild test -project SonosRemote.xcodeproj -scheme SonosRemote -destination 'platform=macOS' -derivedDataPath .build/xcode -only-testing:SonosRemoteTests/TonePresetTests 2>&1 | grep -E "error:|TEST (SUCCEEDED|FAILED)" | tail -3
```
Expected: compile error, cannot find `ToneValue`.

- [ ] **Step 3: Implement**

Append to `SonosRemote/App/TonePreset.swift`:
```swift
enum ToneValue {
    /// "+3", "−2" (U+2212), "0".
    static func string(_ value: Int) -> String {
        if value > 0 { return "+\(value)" }
        if value < 0 { return "−\(-value)" }
        return "0"
    }
}
```

`SonosRemote/Views/Sound/PresetChips.swift`:
```swift
import SwiftUI

/// Flat / Warm / Bright / Custom. `current == nil` lights Custom; Custom itself is not a button.
struct PresetChips: View {
    let current: TonePreset?
    let onSelect: (TonePreset) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(TonePreset.all) { preset in
                Button { onSelect(preset) } label: {
                    Chip(title: preset.name, lit: current == preset)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(preset.name)
                .accessibilityAddTraits(current == preset ? [.isSelected] : [])
            }
            Chip(title: "Custom", lit: current == nil)
                .accessibilityLabel(current == nil ? "Custom, selected" : "Custom")
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}

private struct Chip: View {
    let title: String
    let lit: Bool

    var body: some View {
        Text(title)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(lit ? AnyShapeStyle(Color.accentColor.opacity(0.22)) : AnyShapeStyle(.quaternary.opacity(0.5)), in: Capsule())
            .foregroundStyle(lit ? Color.accentColor : Color.primary)
    }
}
```

`SonosRemote/Views/Sound/ToneSlider.swift` (the old `EQSlider`, restyled for a card row):
```swift
import SwiftUI

/// Integer slider with a label, a signed readout, and double-click-to-zero.
struct ToneSlider: View {
    let label: String
    let value: Int
    let range: ClosedRange<Int>
    let room: String
    let onChange: (Int) -> Void

    @State private var local: Double = 0

    var body: some View {
        Text(label).font(.callout).frame(width: 52, alignment: .leading)
        Slider(value: $local, in: Double(range.lowerBound)...Double(range.upperBound), step: 1) { editing in
            if !editing, Int(local) != value { onChange(Int(local)) }
        }
        .accessibilityLabel("\(label) for \(room)")
        .accessibilityValue("\(Int(local))")
        .onTapGesture(count: 2) { local = 0; onChange(0) }
        Text(ToneValue.string(Int(local)))
            .font(.callout.monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(width: 30, alignment: .trailing)
            .accessibilityHidden(true)
            .onAppear { local = Double(value) }
            .onChange(of: value) { _, new in local = Double(new) }
    }
}
```
(`ToneSlider` renders three siblings so it drops straight into a `CardRow`'s `HStack`.)

`SonosRemote/Views/Sound/SoundScreen.swift` (replace the stub):
```swift
import SwiftUI
import SonosKit

struct SoundScreen: View {
    @Environment(AppState.self) private var state

    private var playerID: String? { state.soundPlayerID ?? state.selectedGroup?.coordinatorID }
    private var player: Player? { playerID.flatMap { state.snapshot.player($0) } }
    private var playerOptions: [(id: String, name: String)] {
        state.snapshot.players
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { ($0.id, $0.name) }
    }

    var body: some View {
        @Bindable var state = state
        VStack(alignment: .leading, spacing: 0) {
            StatusBannerView()
            SectionLabel("TUNING") {
                RoomPicker(title: "Room to tune", selection: $state.soundPlayerID, options: playerOptions)
            }
            if let playerID, let player {
                if let eq = state.eqByPlayer[playerID] {
                    PresetChips(current: TonePreset.matching(eq)) { state.applyPreset($0, player: playerID) }
                    SectionLabel("TONE") {
                        Button("Reset") { state.resetTone(player: playerID) }
                            .buttonStyle(.link)
                            .font(.caption)
                            .accessibilityLabel("Reset tone for \(player.name)")
                    }
                    Card {
                        CardRow(isFirst: true) {
                            ToneSlider(label: "Bass", value: eq.bass, range: EQSettings.bassRange, room: player.name) { new in
                                var next = eq; next.bass = new; state.updateEQ(next, player: playerID)
                            }
                        }
                        CardRow {
                            ToneSlider(label: "Treble", value: eq.treble, range: EQSettings.trebleRange, room: player.name) { new in
                                var next = eq; next.treble = new; state.updateEQ(next, player: playerID)
                            }
                        }
                        if player.hasSub, let sub = eq.subGain {
                            CardRow {
                                ToneSlider(label: "Sub", value: sub, range: EQSettings.subGainRange, room: player.name) { new in
                                    var next = eq; next.subGain = new; state.updateEQ(next, player: playerID)
                                }
                            }
                        }
                    }
                    Card {
                        CardRow(isFirst: true) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Loudness").font(.callout)
                                Text("Boosts bass and treble at low volume").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("Loudness", isOn: Binding(
                                get: { eq.loudness },
                                set: { on in var next = eq; next.loudness = on; state.updateEQ(next, player: playerID) }
                            ))
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .labelsHidden()
                            .accessibilityLabel("Loudness for \(player.name)")
                        }
                    }
                    .padding(.top, 12)
                } else {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Reading EQ…").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .accessibilityElement(children: .combine)
                }
                if let error = state.rowErrors[state.snapshot.group(containing: playerID)?.id ?? playerID] {
                    ErrorLine(text: error)
                }
            } else {
                Text("No room selected")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            }
        }
        .padding(.bottom, 12)
        .task(id: playerID) {
            if let playerID { state.loadEQ(player: playerID) }
        }
    }
}
```

- [ ] **Step 4: Build, test, run**

```bash
xcodegen generate >/dev/null && xcodebuild test -project SonosRemote.xcodeproj -scheme SonosRemote -destination 'platform=macOS' -derivedDataPath .build/xcode 2>&1 | grep -E "error:|Test run with|TEST (SUCCEEDED|FAILED)" | tail -3
pkill -x SonosRemote; open .build/xcode/Build/Products/Debug/SonosRemote.app
```
Expected: 33 tests pass. Owner check on the sliders icon: picker lists every speaker and starts on the selected room's coordinator; "Reading EQ…" then the sliders; Warm lights when bass is +3 and treble −2 and Custom otherwise; Reset zeroes the tone; the Sub row appears only for a room with a sub; Loudness toggles.

- [ ] **Step 5: Commit**

```bash
git add -A SonosRemote SonosRemoteTests
git commit -m "feat(app): sound screen with presets, tone card and loudness"
```

---
### Task 8: Group screen

**Files:**
- Replace: `SonosRemote/Views/Group/GroupScreen.swift` (the Task 4 stub)

**Interfaces:**
- Consumes: `AppState.selectedGroup/snapshot.players/snapshot.group(containing:)/rowErrors/setMembership(of:inGroup:member:)`, `PlaybackDisplay.nowPlayingLine(for:)` (Task 5), `Artwork(url:size:placeholder:)`, `SectionLabel`, `Card`, `CardRow`, `ErrorLine`, `StatusBannerView`, `SonosGroup`.
- Produces: `GroupScreen()` only.

- [ ] **Step 1: Write the view**

`SonosRemote/Views/Group/GroupScreen.swift` (replace the stub):
```swift
import SwiftUI
import SonosKit

struct GroupScreen: View {
    @Environment(AppState.self) private var state

    private var players: [Player] {
        state.snapshot.players.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StatusBannerView()
            if let group = state.selectedGroup {
                HStack(spacing: 12) {
                    Artwork(url: group.nowPlaying?.artworkURL, size: 40, placeholder: "hifispeaker")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.name).font(.callout.weight(.semibold)).lineLimit(1)
                        Text(PlaybackDisplay.nowPlayingLine(for: group)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .accessibilityElement(children: .combine)

                SectionLabel("ROOMS PLAYING TOGETHER")
                Card {
                    ForEach(Array(players.enumerated()), id: \.element.id) { index, player in
                        CardRow(isFirst: index == 0) { MembershipRow(player: player, group: group) }
                    }
                }
                if let error = state.rowErrors[group.id] { ErrorLine(text: error) }
            } else {
                Text("No room selected")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            }
        }
        .padding(.bottom, 12)
    }
}

/// Name, note, switch. The coordinator is on and disabled; a room playing elsewhere says so.
private struct MembershipRow: View {
    @Environment(AppState.self) private var state
    let player: Player
    let group: SonosGroup

    var body: some View {
        let isCoordinator = player.id == group.coordinatorID
        let isMember = group.playerIDs.contains(player.id)
        let elsewhere = state.snapshot.group(containing: player.id)
        let playingElsewhere = !isMember && elsewhere?.playbackState == .playing
        VStack(alignment: .leading, spacing: 2) {
            Text(player.name).font(.callout)
            if isCoordinator {
                Text("Source of this group").font(.caption).foregroundStyle(.secondary)
            } else if playingElsewhere, let now = elsewhere?.nowPlaying {
                Text("Playing \(now.title), will switch to this group")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        Spacer()
        Toggle(isOn: Binding(
            get: { isMember },
            set: { on in state.setMembership(of: player.id, inGroup: group.id, member: on) }
        )) { EmptyView() }
        .toggleStyle(.switch)
        .controlSize(.small)
        .labelsHidden()
        .disabled(isCoordinator)
        .accessibilityLabel(isCoordinator ? "\(player.name), source of this group" : "\(player.name) in \(group.name)")
    }
}
```

- [ ] **Step 2: Build, test, run**

```bash
xcodebuild test -project SonosRemote.xcodeproj -scheme SonosRemote -destination 'platform=macOS' -derivedDataPath .build/xcode 2>&1 | grep -E "error:|Test run with|TEST (SUCCEEDED|FAILED)" | tail -3
pkill -x SonosRemote; open .build/xcode/Build/Products/Debug/SonosRemote.app
```
Expected: 33 tests pass. Owner check via the "Group" link on the main screen: the header says GROUP with the room's art; the source room's switch is on and disabled; switching another room on joins it within a couple of seconds and the main screen's rooms list reflects it; switching it off releases it. Do not regroup the owner's speakers from a script; the owner performs this check.

- [ ] **Step 3: Commit**

```bash
git add -A SonosRemote
git commit -m "feat(app): group screen with membership switches"
```

---

### Task 9: Settings screen

**Files:**
- Replace: `SonosRemote/Views/Settings/SettingsScreen.swift` (the Task 4 stub)
- Create: `SonosRemote/App/AppVersion.swift`
- Modify: `SonosRemote/Views/Shell/FooterView.swift` (use `AppVersion.short`)

**Interfaces:**
- Consumes: `AppState.snapshot.status/snapshot.players/snapshot.softwareVersion/retryDiscovery()`, `KeyboardShortcuts.Name.togglePanel` (declared in `SonosRemote/App/PanelController.swift`; do not move it), `SMAppService`, `SectionLabel`, `Card`, `CardRow`.
- Produces: `AppVersion.short`, `AppVersion.display`.

- [ ] **Step 1: Version helper and footer**

`SonosRemote/App/AppVersion.swift`:
```swift
import Foundation

enum AppVersion {
    /// "0.2.0"
    static var short: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    /// "0.2.0 (12)"
    static var display: String {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(short) (\(build))"
    }
}
```
In `SonosRemote/Views/Shell/FooterView.swift` delete the private `version` property and use `Text("Remote for Sonos \(AppVersion.short)")`.

- [ ] **Step 2: Write the screen**

`SonosRemote/Views/Settings/SettingsScreen.swift` (replace the stub):
```swift
import SwiftUI
import SonosKit
import ServiceManagement
import KeyboardShortcuts

struct SettingsScreen: View {
    @Environment(AppState.self) private var state
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    private static let releasesURL = URL(string: "https://github.com/jens-wedin/sonos-remote/releases")!

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("CONNECTION")
            Card {
                CardRow(isFirst: true) {
                    Circle()
                        .fill(isConnected ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(statusText).font(.callout.weight(.medium))
                        Text(detailText).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { state.retryDiscovery() } label: {
                        Image(systemName: "arrow.clockwise").frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Refresh connection")
                }
            }

            SectionLabel("GENERAL")
            Card {
                CardRow(isFirst: true) {
                    Text("Launch at login").font(.callout)
                    Spacer()
                    Toggle("Launch at login", isOn: $launchAtLogin)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                }
                if let loginError {
                    CardRow { Text(loginError).font(.caption).foregroundStyle(.red) }
                }
                CardRow {
                    Text("Global shortcut").font(.callout)
                    Spacer()
                    KeyboardShortcuts.Recorder(for: .togglePanel)
                        .accessibilityLabel("Global shortcut")
                }
            }

            SectionLabel("SYSTEM")
            Card {
                CardRow(isFirst: true) {
                    Text("Version").font(.callout)
                    Spacer()
                    Text(AppVersion.display).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                }
                CardRow {
                    Link(destination: Self.releasesURL) {
                        HStack {
                            Text("Releases").font(.callout)
                            Spacer()
                            Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .foregroundStyle(.primary)
                    .accessibilityLabel("Releases on GitHub")
                }
            }
        }
        .padding(.bottom, 12)
        .onChange(of: launchAtLogin) { _, on in
            guard on != (SMAppService.mainApp.status == .enabled) else { return }
            do {
                if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                loginError = nil
            } catch {
                loginError = error.localizedDescription
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }

    private var isConnected: Bool {
        if case .ready = state.snapshot.status { return true }
        return false
    }

    private var statusText: String {
        switch state.snapshot.status {
        case .ready: "Connected"
        case .discovering: "Looking for Sonos…"
        case .noPlayersFound: "No Sonos found"
        case .unauthorized: "Not authorized"
        case .localNetworkDenied: "Local network access is off"
        }
    }

    /// "3 speakers · S2 · 85.1-63270"
    private var detailText: String {
        let count = state.snapshot.players.count
        let speakers = count == 1 ? "1 speaker" : "\(count) speakers"
        return [speakers, "S2", state.snapshot.softwareVersion].compactMap { $0 }.joined(separator: " · ")
    }
}
```

- [ ] **Step 3: Build, test, run**

```bash
xcodegen generate >/dev/null && xcodebuild test -project SonosRemote.xcodeproj -scheme SonosRemote -destination 'platform=macOS' -derivedDataPath .build/xcode 2>&1 | grep -E "error:|Test run with|TEST (SUCCEEDED|FAILED)" | tail -3
grep -rn "SettingsOpener\|SettingsView\b" SonosRemote SonosRemoteTests || echo "no references to the old settings window"
pkill -x SonosRemote; open .build/xcode/Build/Products/Debug/SonosRemote.app
```
Expected: 33 tests pass, no references to the old window. Owner check on the gear icon: green dot, "Connected", the speaker count and Sonos version; refresh shows "Looking for Sonos…" then reconnects; launch at login toggles; the recorder records a shortcut that opens the panel; the version matches the footer; Releases opens the browser. No Dock icon appears at any point.

- [ ] **Step 4: Commit**

```bash
git add -A SonosRemote
git commit -m "feat(app): settings screen replaces the settings window"
```

---

### Task 10: Docs, changelog, checklist, knowledge

**Files:**
- Modify: `README.md`, `changelog.md`, `knowledge/procedural/manual-test-checklist.md`, `knowledge/domain/sonos-local-api.md`, `docs/superpowers/specs/2026-09-04-sonos-remote-design.md`, `MEMORY.md`

**Interfaces:** none (documentation only). The version bump and release are the owner's step, after merge: `scripts/release.sh 0.2.0` sets `MARKETING_VERSION` itself; do not edit `project.yml` here.

- [ ] **Step 1: README**

Replace the `## Features (v0.1.0)` section (through the end of `### Not yet`) with the two sections below, and add the `## Panel layout` section directly before the existing `## Layout` section (which describes the repository and stays as it is):
```markdown
## Features (v0.2.0)

- Menu bar panel (420 pt) with one selected room: artwork, title, artist, album, a progress bar with elapsed and remaining time, and shuffle / previous / play-pause / next / repeat.
- Group volume with mute, and a rooms list with a slider per group; playing rooms sort to the top.
- Favorites screen: pick the room, search, play stations, playlists and albums.
- Sound screen: Flat / Warm / Bright presets, bass, treble, sub (when the room has one), loudness, per speaker.
- Group screen: join and release rooms with switches.
- Settings screen: connection status with refresh, launch at login, a global shortcut, version and a link to releases.
- Keyboard: Escape closes, Cmd-[ goes back, Up/Down/Return/Space work in the rooms list, Cmd-Q quits. VoiceOver labels on every control.

### Not yet

Seeking by dragging the progress bar, balance, Speech Enhancement and Night Sound, pinned favorites, album art in the menu bar, in-app update checks. See `docs/superpowers/specs/2026-09-11-panel-redesign-design.md` for the round-2 list.

## Panel layout

The panel has a header (the SONOS label or a back chevron plus the screen name, and three icons: favorites, sound, settings), a body that slides between the main screen and the sub-screens, and a footer with the version and Quit. The main screen is a hero for the selected room, the transport, the group volume and the rooms list; the Group screen opens from the "Group" link above the rooms list. The design mockup is `docs/design/2026-09-11-panel-mockup.png`.
```
Remove any remaining sentence that mentions a Settings window (search for "Settings window" and "Settings…").

- [ ] **Step 2: Changelog**

Under `## [Unreleased]` in `changelog.md` add the notes below. Leave them under Unreleased: `scripts/release.sh` refuses to run until the owner moves them into a `## [0.2.0] - <date>` heading, which happens at release time.
```markdown
### Changed
- New panel design (420 pt): a hero for one selected room with artwork, title, artist and album, a progress bar with elapsed and remaining time, shuffle and repeat next to the transport, the group volume, and a compact rooms list; playing rooms still sort first. Selecting a room replaces opening a row.
- Favorites, Sound (EQ), Group and Settings are screens reached from the header icons and the "Group" link, with a back chevron and Cmd-[ to return; the body slides between screens.
- Settings moved into the panel; the separate Settings window and its Dock-icon activation code are gone.

### Added
- Shuffle and repeat, with the buttons disabled when the speaker reports it cannot.
- Favorites search and type glyphs for stations, playlists and albums.
- Tone presets Flat, Warm and Bright, and a Reset link on the Tone card.
- Connection card on the Settings screen: status, speaker count, Sonos software version, and a refresh button that reruns discovery.
- Version and a Releases link on the Settings screen.
- SonosKit: playback position, duration and play modes on `Group.progress`; `Favorite.kind`; `HouseholdSnapshot.softwareVersion`; `Household.setShuffle` and `setRepeat`.
```

- [ ] **Step 3: Manual test checklist**

Replace items 2, 3, 4, 5, 7 and 9 of `knowledge/procedural/manual-test-checklist.md` with (keep the numbering continuous and the other items as they are):
```markdown
2. Main screen: the selected room's art, title, artist, album; progress bar advances once a second and the remaining time counts down; radio shows only the source line. Shuffle and repeat toggle and light up; the Sonos app agrees.
3. Rooms list: playing rooms first; clicking art or text selects (hero changes, row highlights); each row's slider moves its own group; change a volume in the Sonos app → the slider follows.
4. Favorites (heart): the picker starts on the selected room; search filters and the count updates; a station without artwork shows the radio glyph; clicking a row plays it on the chosen room.
5. Sound (sliders): the picker starts on the selected room's coordinator; values match `sonosctl eq <room>`; Warm lights at +3/−2, Custom otherwise; Reset zeroes bass, treble and sub; sub row only on the Amp; double-click resets one slider; loudness toggles.
7. Keyboard: Escape closes from every screen; Cmd-[ returns to main; Up/Down move through rooms, Return selects, Space toggles play on the focused room; Tab reaches every control. VoiceOver reads the header as a header, each icon by screen name, the back button as "Back".
9. Settings (gear): green dot + "Connected" + "<n> speakers · S2 · <version>"; refresh reruns discovery; launch at login registers; the shortcut records and opens the panel; the version matches the footer; Releases opens the browser. No Dock icon ever appears.
```
Add after the last item:
```markdown
12. Navigation: tapping the active icon returns to main; switching screens slides; the panel height follows the content and scrolls above 640 pt (a household with 10+ favorites).
```

- [ ] **Step 4: Knowledge and old spec**

Append to `knowledge/domain/sonos-local-api.md` under the playback section:
```markdown
- Play modes: `POST /groups/{gid}/playback/playMode` with `{"playModes":{"shuffle":bool,"repeat":bool}}`; always send both keys (the speaker treats a missing key as "leave as is", but a partial body has produced 400s on older firmware). The current modes and the `canShuffle`/`canRepeat` flags arrive in every `playbackStatus` event under `playModes` and `availablePlaybackActions`.
- Position: `playbackStatus.positionMillis` is the position at the moment of the event; the app extrapolates locally while playing. Duration comes from `metadataStatus.currentItem.track.durationMillis` and is absent for radio.
- Software version: `players[].softwareVersion` in `GET /households/local/groups`.
```
At the top of section 5 in `docs/superpowers/specs/2026-09-04-sonos-remote-design.md` add one line: `> Superseded on 2026-09-11 by docs/superpowers/specs/2026-09-11-panel-redesign-design.md; the rest of this document still applies.`

Update `MEMORY.md` (repo root) with a short "Where we are" entry: the redesign round 1 is implemented on this branch, what the owner checks before release (the checklist), and that `scripts/release.sh 0.2.0` is the next step after merge.

- [ ] **Step 5: Verify and commit**

```bash
grep -n "Settings window\|Settings…\|SettingsOpener" README.md knowledge -r || echo "clean"
git add README.md changelog.md knowledge docs MEMORY.md
git commit -m "docs: describe the redesigned panel, update checklist and Sonos API notes"
```

---

## Release (owner, after merge)

Not a task for an implementer. After the branch is merged to `main`: run the manual checklist against the Debug build, then `scripts/release.sh 0.2.0` (Developer ID signing, notarization, GitHub Release, cask update in the tap), as documented in `knowledge/procedural/release.md`.
