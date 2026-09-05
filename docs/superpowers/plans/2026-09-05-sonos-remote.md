# Sonos Remote Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A native macOS menu bar app that lists every Sonos group in the house, with one row open at a time for transport, per-speaker volume, favorites, EQ, and grouping, driven live by the speakers' local API.

**Architecture:** A UI-free Swift package `SonosKit` does Bonjour discovery, REST and websocket traffic to port 1443, SOAP EQ calls to port 1400, and folds everything into immutable `HouseholdSnapshot` values through a pure reducer inside a `Household` actor. The SwiftUI app `SonosRemote` is a `MenuBarExtra` window that observes snapshots through one main-actor `AppState` and sends commands back; it never touches the network.

**Tech Stack:** Swift 6 (strict concurrency), Swift Testing, SwiftPM, XcodeGen, SwiftUI `MenuBarExtra`, Network.framework (`NWBrowser`), Foundation `URLSession` + `URLSessionWebSocketTask`, MenuBarExtraAccess, KeyboardShortcuts, ServiceManagement (`SMAppService`).

**Spec:** `docs/superpowers/specs/2026-09-04-sonos-remote-design.md`. Research with verified API facts: `docs/research/2026-09-04-sonos-macos-research.md`.

## Global Constraints

- App minimum macOS: `26.0`. Package minimum macOS: `15.0` (needs `Synchronization.Mutex`).
- Swift language mode 6 with strict concurrency in every target.
- Third-party dependencies: only `MenuBarExtraAccess` (≥ 1.3.0) and `KeyboardShortcuts` (≥ 3.0.0). Nothing else, no test helpers from outside.
- Local API key header, exact value: `X-Sonos-Api-Key: 123e4567-e89b-12d3-a456-426655440000`.
- Websocket subprotocol, exact value: `v1.api.smartspeaker.audio`. Never send an `Origin` header.
- Self-signed TLS is trusted only for hosts that are private IPv4 addresses **and** were produced by discovery or the groups response.
- App Sandbox on, entitlements exactly: `com.apple.security.app-sandbox`, `com.apple.security.network.client`.
- Info.plist must carry `LSUIElement`, `NSLocalNetworkUsageDescription`, `NSBonjourServices` = `["_sonos._tcp"]`, `NSAppTransportSecurity.NSAllowsLocalNetworking`.
- Every shell command that builds Swift must run with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` exported, because `xcode-select` on this Mac points at the Command Line Tools. Never run `sudo xcode-select`.
- Package commands run from `Packages/SonosKit`. App commands run from the repo root.
- Conventional commits. Commit at the end of every task. Never commit the generated `SonosRemote.xcodeproj`, `.build/`, or `.superpowers/`.
- Rows in the panel are **groups**, not players. Exactly one row open at a time. Toggles (switches), never checkboxes.
- Fixtures under `Packages/SonosKit/Tests/SonosKitTests/Fixtures/` were captured from the real system on 2026-09-04 and are already committed. Do not edit them. Their contents are described in Task 1.

---

## File Structure

```
Packages/SonosKit/
  Package.swift
  Sources/SonosKit/
    Models/Models.swift                 public domain types: Player, Group, Volume, NowPlaying, Favorite, EQSettings, PlaybackState
    Models/HouseholdSnapshot.swift      HouseholdSnapshot + HouseholdStatus
    Wire/WireTypes.swift                internal Decodable mirrors of the JSON the speakers send
    Wire/WireMapping.swift              wire → domain conversions (one init per domain type)
    Socket/SocketFrame.swift            [header, body] framing, SocketEvent, subscribe/unsubscribe encoding
    Socket/Backoff.swift                pure reconnect delay schedule
    Socket/PlayerSocket.swift           actor: one websocket per player, reconnect, subscriptions
    Reducer/HouseholdEvent.swift        every fact that can change the snapshot
    Reducer/SnapshotReducer.swift       pure (snapshot, event) → snapshot
    Transport/Transport.swift           APIRequest, APIResponse, Transport, SocketConnection protocols
    Transport/TrustPolicy.swift         private-IPv4 check + TrustStore allowlist
    Transport/URLSessionTransport.swift real Transport over URLSession with trust delegate
    LocalAPI/LocalAPIError.swift        typed errors mapped from speaker error bodies
    LocalAPI/LocalAPIClient.swift       REST calls to :1443
    UPnP/SOAP.swift                     envelope building + value extraction
    UPnP/UPnPClient.swift               EQ calls to :1400
    Discovery/Discovering.swift         DiscoveredPlayer, DiscoveryEvent, Discovering protocol
    Discovery/BonjourDiscovery.swift    NWBrowser implementation + TXT parsing
    Household/SubscriptionPlan.swift    pure: which socket subscribes to what
    Household/Household.swift           the actor that owns everything
  Sources/sonosctl/main.swift           manual integration CLI
  Tests/SonosKitTests/
    Fixtures/                           real captured responses (already present)
    Support/Fixtures.swift              fixture loader
    Support/FakeTransport.swift         records requests, returns stubs, hands out FakeSocketConnection
    Support/FakeSocketConnection.swift  push messages into a PlayerSocket
    Support/FakeDiscovery.swift         emit discovery events on demand
    Support/Wait.swift                  polling helper for async assertions
    ModelsTests.swift, SocketFrameTests.swift, ReducerTests.swift, TrustPolicyTests.swift,
    LocalAPIClientTests.swift, BackoffTests.swift, PlayerSocketTests.swift, SOAPTests.swift,
    UPnPClientTests.swift, DiscoveryTests.swift, SubscriptionPlanTests.swift, HouseholdTests.swift

project.yml                              XcodeGen spec (generates SonosRemote.xcodeproj, git-ignored)
SonosRemote/
  App/SonosRemoteApp.swift               MenuBarExtra scene, Settings scene, shortcut wiring
  App/PanelController.swift              @Observable isPresented bridge for MenuBarExtraAccess + hotkey
  App/AppState.swift                     @MainActor @Observable: snapshot, open row, commands, errors
  App/RowOpenPolicy.swift                pure: which row is open after a snapshot
  App/VolumeCommandGate.swift            pure: slider send throttle + incoming suppression
  App/SettingsOpener.swift               activation-policy dance to show the Settings window
  Views/PanelView.swift                  header, banner, scrolling group list, footer
  Views/GroupRowView.swift               closed/open switch per group
  Views/ClosedRowView.swift              art, name, badge, track, live slider
  Views/OpenRowView.swift                big art, transport, volumes, tabs
  Views/TransportView.swift              previous / play-pause / next
  Views/VolumeSliderView.swift           labelled slider + mute, uses VolumeCommandGate
  Views/FavoritesTabView.swift
  Views/EQTabView.swift
  Views/GroupTabView.swift
  Views/StatusBannerView.swift           discovering / none found / unauthorized / local network denied
  Views/FooterView.swift                 Settings… and Quit
  Views/SettingsView.swift               launch at login + shortcut recorder
  Views/Artwork.swift                    AsyncImage wrapper with placeholder
SonosRemoteTests/
  RowOpenPolicyTests.swift
  VolumeCommandGateTests.swift
README.md, changelog.md, knowledge/INDEX.md, knowledge/ERRORS.md,
knowledge/domain/sonos-local-api.md, knowledge/procedural/build-and-run.md
```

**Interfaces that every task relies on** (defined in Tasks 2–5, repeated here so any task can be read alone):

```swift
// Domain (Task 2)
public enum PlaybackState: String, Sendable, Codable, Hashable { case playing = "PLAYBACK_STATE_PLAYING", paused = "PLAYBACK_STATE_PAUSED", idle = "PLAYBACK_STATE_IDLE", buffering = "PLAYBACK_STATE_BUFFERING" }
public struct Volume: Hashable, Sendable { public var level: Int; public var muted: Bool; public var fixed: Bool }
public struct NowPlaying: Hashable, Sendable { public var title: String; public var artist: String?; public var album: String?; public var artworkURL: URL?; public var serviceName: String?; public var containerName: String? }
public struct Player: Identifiable, Hashable, Sendable { public let id: String; public var name: String; public var address: String; public var hasSub: Bool }
public struct Group: Identifiable, Hashable, Sendable { public let id: String; public var name: String; public var coordinatorID: String; public var playerIDs: [String]; public var playbackState: PlaybackState; public var volume: Volume; public var nowPlaying: NowPlaying? }
public struct Favorite: Identifiable, Hashable, Sendable { public let id: String; public var name: String; public var subtitle: String?; public var imageURL: URL?; public var serviceName: String? }
public struct EQSettings: Hashable, Sendable { public var bass: Int; public var treble: Int; public var loudness: Bool; public var subGain: Int? }
public enum HouseholdStatus: Sendable, Hashable { case discovering, ready, noPlayersFound, unauthorized, localNetworkDenied }
public struct HouseholdSnapshot: Sendable, Hashable { public var status: HouseholdStatus; public var groups: [Group]; public var players: [Player]; public var favorites: [Favorite]; public var playerVolumes: [String: Volume] }

// Transport (Task 5)
public struct APIRequest: Sendable, Hashable { public var method: String; public var url: URL; public var headers: [String: String]; public var body: Data? }
public struct APIResponse: Sendable { public var status: Int; public var body: Data }
public protocol SocketConnection: Sendable { func send(_ data: Data) async throws; func messages() -> AsyncThrowingStream<Data, any Error>; func ping() async throws; func close() }
public protocol Transport: Sendable { func send(_ request: APIRequest) async throws -> APIResponse; func openSocket(_ url: URL, headers: [String: String], protocols: [String]) async throws -> any SocketConnection }

// Household (Task 11)
public actor Household {
  public init(discovery: any Discovering, transport: any Transport, trustStore: TrustStore? = nil, configuration: Configuration = .init())
  public func start(); public func stop()
  public var current: HouseholdSnapshot { get }
  public func snapshots() -> AsyncStream<HouseholdSnapshot>
  public func play(group: String) async throws; pause(group:); next(group:); previous(group:)
  public func setGroupVolume(_ level: Int, group: String) async throws; setGroupMuted(_:group:)
  public func setPlayerVolume(_ level: Int, player: String) async throws; setPlayerMuted(_:player:)
  public func playFavorite(_ favoriteID: String, group: String) async throws
  public func setGroupMembers(_ playerIDs: [String], group: String) async throws
  public func eq(player: String) async throws -> EQSettings; public func setEQ(_ eq: EQSettings, player: String) async throws
}
```

---

### Task 1: Package scaffold, fixture loader, repo docs skeleton

**Files:**
- Create: `Packages/SonosKit/Package.swift`
- Create: `Packages/SonosKit/Sources/SonosKit/SonosKit.swift`
- Create: `Packages/SonosKit/Sources/sonosctl/main.swift` (placeholder that prints usage; real commands come in Task 12)
- Create: `Packages/SonosKit/Tests/SonosKitTests/Support/Fixtures.swift`
- Create: `Packages/SonosKit/Tests/SonosKitTests/FixturesTests.swift`
- Create: `README.md`, `changelog.md`, `knowledge/INDEX.md`, `knowledge/ERRORS.md`, `knowledge/domain/sonos-local-api.md`, `knowledge/procedural/build-and-run.md`
- Already present, do not edit: `Packages/SonosKit/Tests/SonosKitTests/Fixtures/*`

**Interfaces:**
- Produces: `enum Fixtures { static func data(_ name: String) -> Data; static func string(_ name: String) -> String; static func lines(_ name: String) -> [String] }` in the test target.

**What the fixtures contain** (captured 2026-09-04 while "Flyttbar + 1" was playing Spotify):

| File | Content |
|---|---|
| `groups.json` | `GET /households/local/groups`. 3 groups: "Sovrum" (coordinator `RINCON_48A6B8194D2A01400`, idle), "Elsas Sovrum" (`RINCON_347E5C5091CE01400`, idle), "Flyttbar + 1" (id `RINCON_542A1B73A25001400:620674909`, coordinator `RINCON_542A1B73A25001400`, `PLAYBACK_STATE_PLAYING`, playerIds `["RINCON_347E5C04E98101400", "RINCON_542A1B73A25001400"]`). 4 players: Stereo `RINCON_347E5C04E98101400` at `wss://192.168.1.105:1443/websocket/api`, Sovrum `RINCON_48A6B8194D2A01400` at 192.168.1.28, Elsas Sovrum `RINCON_347E5C5091CE01400` at 192.168.1.250, Flyttbar `RINCON_542A1B73A25001400` at 192.168.1.216. |
| `playbackMetadata.json` | container name "R&B-mix", type `playlist.spotify.connect`, service "Spotify"; currentItem.track name "Off the Wall", artist "Michael Jackson", album "Off the Wall", imageUrl `https://i.scdn.co/image/ab67616d0000b2732b74bf21c7e4f56758610949`. |
| `playback.json` | `playbackState: PLAYBACK_STATE_PLAYING`, positionMillis 80000. |
| `groupVolume.json` | `{"volume":5,"muted":false,"fixed":false}` |
| `playerVolume.json` | `{"volume":8,"muted":false,"fixed":false}` |
| `favorites.json` | one item: id "3", name "P3", description "Sveriges Radio", service name "Sveriges Radio", imageUrl on static-cdn.sr.se. |
| `playerInfo.json` | `GET /players/{id}/info` for the Amp; `device.modelDisplayName` "Amp", `deviceFeatures` includes `SUB_OUT`. |
| `events.jsonl` | 13 websocket messages in order: subscribe ack + state for playback, playbackMetadata, groupVolume, playerVolume (player `RINCON_542A1B73A25001400`, volume 2), groups (3 groups, 4 players, **no** playbackState field), favorites (ack + `versionChanged`), then a `globalError` with `ERROR_UNSUPPORTED_NAMESPACE` for a bogus namespace. Group id in the events: `RINCON_542A1B73A25001400:620674909`. |
| `error_400_nokey.json` | `{"_objectType":"globalError","errorCode":"ERROR_API_KEY_VALIDATION_FAILED","reason":"Invalid api key"}` |
| `error_404_coordinator_moved.json` | `{"_objectType":"groupCoordinatorChanged","groupStatus":"GROUP_STATUS_MOVED","groupName":"Flyttbar + 1","websocketUrl":"wss://192.168.1.216:1443/websocket/api","playerId":"RINCON_542A1B73A25001400"}` |
| `error_unknown_group.json` | `{"_objectType":"groupCoordinatorChanged","groupStatus":"GROUP_STATUS_GONE"}` |
| `soap_GetBass.xml` | `GetBassResponse` with `<CurrentBass>-3</CurrentBass>` |
| `soap_SetBass.xml` | empty `SetBassResponse` |
| `soap_GetEQ_SubGain.xml` | `GetEQResponse` with `<CurrentValue>-2</CurrentValue>` |
| `soap_GetLoudness.xml` | `<CurrentLoudness>1</CurrentLoudness>` |
| `soap_fault.xml` | SOAP Fault with `<errorCode>402</errorCode>` |

- [ ] **Step 1: Write Package.swift**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SonosKit",
    platforms: [.macOS("15.0")],
    products: [
        .library(name: "SonosKit", targets: ["SonosKit"]),
        .executable(name: "sonosctl", targets: ["sonosctl"]),
    ],
    targets: [
        .target(name: "SonosKit"),
        .executableTarget(name: "sonosctl", dependencies: ["SonosKit"]),
        .testTarget(
            name: "SonosKitTests",
            dependencies: ["SonosKit"],
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
```

- [ ] **Step 2: Write the two source placeholders**

`Packages/SonosKit/Sources/SonosKit/SonosKit.swift`:
```swift
/// SonosKit talks to Sonos S2 players on the local network. See README.md.
public enum SonosKit {
    public static let version = "0.1.0"
}
```

`Packages/SonosKit/Sources/sonosctl/main.swift`:
```swift
import Foundation

print("sonosctl: commands arrive in a later task")
exit(0)
```

- [ ] **Step 3: Write the fixture loader and its failing test**

`Packages/SonosKit/Tests/SonosKitTests/Support/Fixtures.swift`:
```swift
import Foundation

enum Fixtures {
    static func url(_ name: String) -> URL {
        let parts = name.split(separator: ".", maxSplits: 1).map(String.init)
        guard let url = Bundle.module.url(forResource: parts[0], withExtension: parts[1], subdirectory: "Fixtures") else {
            fatalError("Missing fixture \(name)")
        }
        return url
    }

    static func data(_ name: String) -> Data {
        try! Data(contentsOf: url(name))
    }

    static func string(_ name: String) -> String {
        String(decoding: data(name), as: UTF8.self)
    }

    /// Non-empty lines of a .jsonl fixture, in file order.
    static func lines(_ name: String) -> [String] {
        string(name).split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }
}
```

`Packages/SonosKit/Tests/SonosKitTests/FixturesTests.swift`:
```swift
import Testing
@testable import SonosKit

@Suite struct FixturesTests {
    @Test func fixturesAreBundled() {
        #expect(Fixtures.data("groups.json").count > 1000)
        #expect(Fixtures.lines("events.jsonl").count == 13)
        #expect(Fixtures.string("soap_fault.xml").contains("<errorCode>402</errorCode>"))
        #expect(SonosKit.version == "0.1.0")
    }
}
```

- [ ] **Step 4: Run the test and make sure it passes**

```bash
cd Packages/SonosKit
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test 2>&1 | tail -5
```
Expected: `Test run with 1 test passed`. If `Bundle.module` is missing, check the `resources:` line in Package.swift.

- [ ] **Step 5: Write the repo docs skeleton**

`README.md`:
```markdown
# Sonos Remote

A native macOS menu bar app that controls a Sonos S2 system over the local network. No Sonos account, no cloud.

- Every group in the house is a row; the open row has transport, per-speaker volume, favorites, EQ, and grouping.
- Speakers are found with Bonjour and driven through the local Control API on port 1443 (REST + websocket). EQ uses UPnP on port 1400.
- Personal project by Jens Wedin. Built for macOS 26.

## Layout

- `Packages/SonosKit` — UI-free Swift package: discovery, API clients, reducer, `Household` actor, `sonosctl` CLI.
- `SonosRemote` — SwiftUI menu bar app. Project file generated by XcodeGen from `project.yml`.
- `docs/` — research and design spec. `knowledge/` — domain and procedural notes.

## Build and test

See `knowledge/procedural/build-and-run.md`. Short version:

    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
    (cd Packages/SonosKit && swift test)
    xcodegen generate && xcodebuild -project SonosRemote.xcodeproj -scheme SonosRemote -configuration Debug -derivedDataPath .build/xcode build
```

`changelog.md`:
```markdown
# Changelog

All notable changes to this project are documented here. Format follows Keep a Changelog; versions follow SemVer.

## [Unreleased]

### Added
- SonosKit package scaffold with fixture-backed tests.
```

`knowledge/INDEX.md`:
```markdown
# Knowledge index

Read top-down; open only what you need.

- `domain/sonos-local-api.md` — how the speakers' local API behaves (ports, headers, message shapes, quirks).
- `procedural/build-and-run.md` — exact commands to test the package, generate the project, build, run.
- `ERRORS.md` — error log with conclusions.
```

`knowledge/ERRORS.md`:
```markdown
# Errors

Log format: date, what happened, deterministic or infrastructure, conclusion (if any).

| Date | Error | Kind | Conclusion |
|---|---|---|---|
| 2026-09-03 | Raw SSDP multicast from a shell process: `OSError: [Errno 65] No route to host` | Deterministic | macOS Local Network privacy blocks multicast for non-entitled processes. Use Bonjour (`NWBrowser`) instead. |
```

`knowledge/domain/sonos-local-api.md`:
```markdown
# Sonos local API (verified on Jens's S2 system, firmware 96.x)

- Discovery: Bonjour `_sonos._tcp`. TXT keys: `uuid` (RINCON_…), `hhid`, `location` (http://IP:1400/xml/device_description.xml), `sslport` 1443, `wss` /websocket/api, `variant` 2 = S2.
- REST: `https://IP:1443/api/v1/...`, header `X-Sonos-Api-Key: 123e4567-e89b-12d3-a456-426655440000`, self-signed cert, responses use `Connection: Close`.
- Group-scoped calls must go to the group's coordinator. Sent to a member you get 404 `groupCoordinatorChanged` with `GROUP_STATUS_MOVED` + `playerId` of the coordinator, or `GROUP_STATUS_GONE`.
- Missing key → 400 `globalError` `ERROR_API_KEY_VALIDATION_FAILED`. Authentication switched on in the Sonos app → 401 `ERROR_NOT_AUTHORIZED`.
- Websocket: `wss://IP:1443/websocket/api`, subprotocol `v1.api.smartspeaker.audio`, same key header, no Origin. Frames are JSON arrays `[header, body]`. Subscribe: `[{"namespace":"playback:1","command":"subscribe","groupId":"…"},{}]`. Ack has `response:"subscribe"`, `success:true`, `type:"none"`; the current state is pushed right after. Unknown namespace → `type:"globalError"`, `ERROR_UNSUPPORTED_NAMESPACE`.
- The `groups` event body has no `playbackState`; the REST groups response does.
- Favorites events are `versionChanged`; re-fetch the list over REST.
- EQ is not in the 1443 API. UPnP `RenderingControl` on `http://IP:1400/MediaRenderer/RenderingControl/Control`: GetBass/SetBass, GetTreble/SetTreble, GetLoudness/SetLoudness (Channel Master), GetEQ/SetEQ with EQType SubGain, SubCrossover. Unsupported EQType → HTTP 500 SOAP fault errorCode 402.
- Sub detection: `GetEQ SubCrossover` > 0 means a sub is attached (Amp reports 99, others 0).
```

`knowledge/procedural/build-and-run.md`:
```markdown
# Build and run

Xcode 26 is installed but `xcode-select` points at the Command Line Tools. Export this in every shell:

    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

## Package

    cd Packages/SonosKit
    swift test                       # all tests
    swift test --filter ReducerTests # one suite
    swift run sonosctl list          # against the real speakers (Terminal needs Local Network permission)

## App

    xcodegen generate                # writes SonosRemote.xcodeproj (git-ignored)
    xcodebuild -project SonosRemote.xcodeproj -scheme SonosRemote -configuration Debug -derivedDataPath .build/xcode build 2>&1 | tail -3
    open .build/xcode/Build/Products/Debug/SonosRemote.app
    xcodebuild test -project SonosRemote.xcodeproj -scheme SonosRemote -destination 'platform=macOS' -derivedDataPath .build/xcode 2>&1 | tail -5

Quit a running copy before launching a new build: `pkill -x SonosRemote`.
```

- [ ] **Step 6: Commit**

```bash
git add Packages/SonosKit README.md changelog.md knowledge
git commit -m "chore: scaffold SonosKit package with fixtures and repo docs"
```

---

### Task 2: Domain models, wire types, mapping

**Files:**
- Create: `Packages/SonosKit/Sources/SonosKit/Models/Models.swift`
- Create: `Packages/SonosKit/Sources/SonosKit/Models/HouseholdSnapshot.swift`
- Create: `Packages/SonosKit/Sources/SonosKit/Wire/WireTypes.swift`
- Create: `Packages/SonosKit/Sources/SonosKit/Wire/WireMapping.swift`
- Test: `Packages/SonosKit/Tests/SonosKitTests/ModelsTests.swift`

**Interfaces:**
- Produces the domain types listed in "Interfaces that every task relies on", plus internal wire types: `GroupsResponse { groups: [WireGroup]; players: [WirePlayer] }`, `WireGroup { id, name, coordinatorId, playbackState: String?, playerIds }`, `WirePlayer { id, name, websocketUrl }`, `WireVolume { volume, muted, fixed }`, `WirePlaybackStatus { playbackState }`, `WireMetadataStatus`, `WireFavoritesList { items }`, `WireGlobalError { errorCode, reason }`, `WireCoordinatorChanged { groupStatus, playerId, websocketUrl }`, `WireObjectType { objectType }`.
- Produces mapping inits: `Volume(wire:)`, `PlaybackState(wireValue:)`, `NowPlaying(wire:)` (failable), `Player(wire:hasSub:)`, `Favorite(wire:)`, `WirePlayer.address` (static `host(fromWebsocketURL:)`).

- [ ] **Step 1: Write the failing tests**

`Packages/SonosKit/Tests/SonosKitTests/ModelsTests.swift`:
```swift
import Foundation
import Testing
@testable import SonosKit

@Suite struct ModelsTests {
    let decoder = JSONDecoder()

    @Test func decodesGroupsFixture() throws {
        let response = try decoder.decode(GroupsResponse.self, from: Fixtures.data("groups.json"))
        #expect(response.groups.count == 3)
        #expect(response.players.count == 4)
        let flyttbar = try #require(response.groups.first { $0.name == "Flyttbar + 1" })
        #expect(flyttbar.id == "RINCON_542A1B73A25001400:620674909")
        #expect(flyttbar.coordinatorId == "RINCON_542A1B73A25001400")
        #expect(flyttbar.playerIds == ["RINCON_347E5C04E98101400", "RINCON_542A1B73A25001400"])
        #expect(flyttbar.playbackState == "PLAYBACK_STATE_PLAYING")
        let stereo = try #require(response.players.first { $0.name == "Stereo" })
        #expect(stereo.websocketUrl == "wss://192.168.1.105:1443/websocket/api")
    }

    @Test func playerAddressComesFromWebsocketURL() {
        let wire = WirePlayer(id: "RINCON_1", name: "Stereo", websocketUrl: "wss://192.168.1.105:1443/websocket/api")
        let player = Player(wire: wire, hasSub: true)
        #expect(player.id == "RINCON_1")
        #expect(player.address == "192.168.1.105")
        #expect(player.hasSub)
        #expect(WirePlayer.host(fromWebsocketURL: "garbage") == nil)
    }

    @Test func decodesMetadataIntoNowPlaying() throws {
        let wire = try decoder.decode(WireMetadataStatus.self, from: Fixtures.data("playbackMetadata.json"))
        let nowPlaying = try #require(NowPlaying(wire: wire))
        #expect(nowPlaying.title == "Off the Wall")
        #expect(nowPlaying.artist == "Michael Jackson")
        #expect(nowPlaying.album == "Off the Wall")
        #expect(nowPlaying.artworkURL?.host() == "i.scdn.co")
        #expect(nowPlaying.serviceName == "Spotify")
        #expect(nowPlaying.containerName == "R&B-mix")
    }

    @Test func metadataWithoutTrackOrContainerIsNil() {
        let wire = WireMetadataStatus(container: nil, currentItem: nil)
        #expect(NowPlaying(wire: wire) == nil)
    }

    @Test func radioMetadataFallsBackToContainerName() {
        let wire = WireMetadataStatus(
            container: WireContainer(name: "P3", service: WireService(name: "Sveriges Radio")),
            currentItem: WireQueueItem(track: WireTrack(name: nil, imageUrl: nil, album: nil, artist: nil, service: nil))
        )
        let nowPlaying = NowPlaying(wire: wire)
        #expect(nowPlaying?.title == "P3")
        #expect(nowPlaying?.serviceName == "Sveriges Radio")
    }

    @Test func decodesVolumeAndPlaybackStatus() throws {
        let volume = try decoder.decode(WireVolume.self, from: Fixtures.data("groupVolume.json"))
        #expect(Volume(wire: volume) == Volume(level: 5, muted: false, fixed: false))
        let status = try decoder.decode(WirePlaybackStatus.self, from: Fixtures.data("playback.json"))
        #expect(PlaybackState(wireValue: status.playbackState) == .playing)
        #expect(PlaybackState(wireValue: "PLAYBACK_STATE_SOMETHING_NEW") == .idle)
    }

    @Test func decodesFavorites() throws {
        let list = try decoder.decode(WireFavoritesList.self, from: Fixtures.data("favorites.json"))
        let favorites = list.items.map(Favorite.init(wire:))
        #expect(favorites.count == 1)
        #expect(favorites[0].id == "3")
        #expect(favorites[0].name == "P3")
        #expect(favorites[0].subtitle == "Sveriges Radio")
        #expect(favorites[0].serviceName == "Sveriges Radio")
        #expect(favorites[0].imageURL?.host() == "static-cdn.sr.se")
    }

    @Test func decodesErrorBodies() throws {
        let type = try decoder.decode(WireObjectType.self, from: Fixtures.data("error_400_nokey.json"))
        #expect(type.objectType == "globalError")
        let global = try decoder.decode(WireGlobalError.self, from: Fixtures.data("error_400_nokey.json"))
        #expect(global.errorCode == "ERROR_API_KEY_VALIDATION_FAILED")
        let moved = try decoder.decode(WireCoordinatorChanged.self, from: Fixtures.data("error_404_coordinator_moved.json"))
        #expect(moved.groupStatus == "GROUP_STATUS_MOVED")
        #expect(moved.playerId == "RINCON_542A1B73A25001400")
        let gone = try decoder.decode(WireCoordinatorChanged.self, from: Fixtures.data("error_unknown_group.json"))
        #expect(gone.groupStatus == "GROUP_STATUS_GONE")
        #expect(gone.playerId == nil)
    }

    @Test func emptySnapshotDefaults() {
        let snapshot = HouseholdSnapshot()
        #expect(snapshot.status == .discovering)
        #expect(snapshot.groups.isEmpty)
        #expect(snapshot.playerVolumes.isEmpty)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
swift test --filter ModelsTests 2>&1 | tail -5
```
Expected: compile errors, `cannot find 'GroupsResponse' in scope` and similar.

- [ ] **Step 3: Write the domain models**

`Packages/SonosKit/Sources/SonosKit/Models/Models.swift`:
```swift
import Foundation

public enum PlaybackState: String, Sendable, Codable, Hashable {
    case playing = "PLAYBACK_STATE_PLAYING"
    case paused = "PLAYBACK_STATE_PAUSED"
    case idle = "PLAYBACK_STATE_IDLE"
    case buffering = "PLAYBACK_STATE_BUFFERING"

    /// Unknown wire values become `.idle` so a new firmware never crashes the app.
    public init(wireValue: String) {
        self = PlaybackState(rawValue: wireValue) ?? .idle
    }
}

public struct Volume: Hashable, Sendable {
    public var level: Int
    public var muted: Bool
    public var fixed: Bool

    public init(level: Int, muted: Bool, fixed: Bool) {
        self.level = level
        self.muted = muted
        self.fixed = fixed
    }

    public static let silent = Volume(level: 0, muted: false, fixed: false)
}

public struct NowPlaying: Hashable, Sendable {
    public var title: String
    public var artist: String?
    public var album: String?
    public var artworkURL: URL?
    public var serviceName: String?
    public var containerName: String?

    public init(title: String, artist: String? = nil, album: String? = nil, artworkURL: URL? = nil, serviceName: String? = nil, containerName: String? = nil) {
        self.title = title
        self.artist = artist
        self.album = album
        self.artworkURL = artworkURL
        self.serviceName = serviceName
        self.containerName = containerName
    }
}

public struct Player: Identifiable, Hashable, Sendable {
    public let id: String
    public var name: String
    /// IPv4 address the player answers on (ports 1443 and 1400).
    public var address: String
    public var hasSub: Bool

    public init(id: String, name: String, address: String, hasSub: Bool) {
        self.id = id
        self.name = name
        self.address = address
        self.hasSub = hasSub
    }
}

public struct Group: Identifiable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var coordinatorID: String
    public var playerIDs: [String]
    public var playbackState: PlaybackState
    public var volume: Volume
    public var nowPlaying: NowPlaying?

    public init(id: String, name: String, coordinatorID: String, playerIDs: [String], playbackState: PlaybackState, volume: Volume, nowPlaying: NowPlaying?) {
        self.id = id
        self.name = name
        self.coordinatorID = coordinatorID
        self.playerIDs = playerIDs
        self.playbackState = playbackState
        self.volume = volume
        self.nowPlaying = nowPlaying
    }
}

public struct Favorite: Identifiable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var subtitle: String?
    public var imageURL: URL?
    public var serviceName: String?

    public init(id: String, name: String, subtitle: String? = nil, imageURL: URL? = nil, serviceName: String? = nil) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.imageURL = imageURL
        self.serviceName = serviceName
    }
}

public struct EQSettings: Hashable, Sendable {
    public var bass: Int
    public var treble: Int
    public var loudness: Bool
    /// nil when the player has no sub.
    public var subGain: Int?

    public init(bass: Int, treble: Int, loudness: Bool, subGain: Int?) {
        self.bass = bass
        self.treble = treble
        self.loudness = loudness
        self.subGain = subGain
    }

    public static let bassRange = -10...10
    public static let trebleRange = -10...10
    public static let subGainRange = -15...15
}
```

`Packages/SonosKit/Sources/SonosKit/Models/HouseholdSnapshot.swift`:
```swift
import Foundation

public enum HouseholdStatus: Sendable, Hashable {
    case discovering
    case ready
    case noPlayersFound
    case unauthorized
    case localNetworkDenied
}

public struct HouseholdSnapshot: Sendable, Hashable {
    public var status: HouseholdStatus
    public var groups: [Group]
    public var players: [Player]
    public var favorites: [Favorite]
    public var playerVolumes: [String: Volume]

    public init(status: HouseholdStatus = .discovering, groups: [Group] = [], players: [Player] = [], favorites: [Favorite] = [], playerVolumes: [String: Volume] = [:]) {
        self.status = status
        self.groups = groups
        self.players = players
        self.favorites = favorites
        self.playerVolumes = playerVolumes
    }

    public func group(_ id: String) -> Group? { groups.first { $0.id == id } }
    public func player(_ id: String) -> Player? { players.first { $0.id == id } }
    public func group(containing playerID: String) -> Group? { groups.first { $0.playerIDs.contains(playerID) } }
}
```

- [ ] **Step 4: Write the wire types and mapping**

`Packages/SonosKit/Sources/SonosKit/Wire/WireTypes.swift`:
```swift
import Foundation

// Internal mirrors of the JSON the speakers send. Every field that Sonos may omit is optional.
// Unknown keys are ignored by JSONDecoder, which is what we want for forward compatibility.

struct WireObjectType: Decodable {
    var objectType: String
    enum CodingKeys: String, CodingKey { case objectType = "_objectType" }
}

struct GroupsResponse: Decodable, Sendable {
    var groups: [WireGroup]
    var players: [WirePlayer]
}

struct WireGroup: Decodable, Hashable, Sendable {
    var id: String
    var name: String
    var coordinatorId: String
    var playbackState: String?
    var playerIds: [String]
}

struct WirePlayer: Decodable, Hashable, Sendable {
    var id: String
    var name: String
    var websocketUrl: String

    static func host(fromWebsocketURL string: String) -> String? {
        URLComponents(string: string)?.host
    }
}

struct WireVolume: Decodable, Sendable {
    var volume: Int
    var muted: Bool
    var fixed: Bool
}

struct WirePlaybackStatus: Decodable, Sendable {
    var playbackState: String
}

struct WireService: Decodable, Sendable {
    var name: String?
}

struct WireNamed: Decodable, Sendable {
    var name: String?
}

struct WireTrack: Decodable, Sendable {
    var name: String?
    var imageUrl: String?
    var album: WireNamed?
    var artist: WireNamed?
    var service: WireService?
}

struct WireQueueItem: Decodable, Sendable {
    var track: WireTrack?
}

struct WireContainer: Decodable, Sendable {
    var name: String?
    var service: WireService?
}

struct WireMetadataStatus: Decodable, Sendable {
    var container: WireContainer?
    var currentItem: WireQueueItem?
}

struct WireFavorite: Decodable, Sendable {
    var id: String
    var name: String
    var description: String?
    var imageUrl: String?
    var service: WireService?
}

struct WireFavoritesList: Decodable, Sendable {
    var version: String?
    var items: [WireFavorite]
}

struct WireVersionChanged: Decodable, Sendable {
    var version: String?
}

struct WireGlobalError: Decodable, Sendable {
    var errorCode: String
    var reason: String?
}

struct WireCoordinatorChanged: Decodable, Sendable {
    var groupStatus: String
    var playerId: String?
    var websocketUrl: String?
}
```

`Packages/SonosKit/Sources/SonosKit/Wire/WireMapping.swift`:
```swift
import Foundation

extension Volume {
    init(wire: WireVolume) {
        self.init(level: wire.volume, muted: wire.muted, fixed: wire.fixed)
    }
}

extension Player {
    init(wire: WirePlayer, hasSub: Bool) {
        self.init(id: wire.id, name: wire.name, address: WirePlayer.host(fromWebsocketURL: wire.websocketUrl) ?? "", hasSub: hasSub)
    }
}

extension NowPlaying {
    /// nil when there is neither a track name nor a container name (nothing loaded).
    init?(wire: WireMetadataStatus) {
        let track = wire.currentItem?.track
        guard let title = track?.name ?? wire.container?.name, !title.isEmpty else { return nil }
        self.init(
            title: title,
            artist: track?.artist?.name,
            album: track?.album?.name,
            artworkURL: track?.imageUrl.flatMap(URL.init(string:)),
            serviceName: track?.service?.name ?? wire.container?.service?.name,
            containerName: wire.container?.name
        )
    }
}

extension Favorite {
    init(wire: WireFavorite) {
        self.init(
            id: wire.id,
            name: wire.name,
            subtitle: wire.description,
            imageURL: wire.imageUrl.flatMap(URL.init(string:)),
            serviceName: wire.service?.name
        )
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
swift test --filter ModelsTests 2>&1 | tail -5
```
Expected: `9 tests passed`. If `URL.host()` is unavailable, use `.host` (the property) instead; both exist on macOS 15.

- [ ] **Step 6: Commit**

```bash
git add Packages/SonosKit
git commit -m "feat(sonoskit): add domain models, wire types and mapping"
```

---
### Task 3: Websocket framing and SocketEvent

**Files:**
- Create: `Packages/SonosKit/Sources/SonosKit/Socket/SocketFrame.swift`
- Test: `Packages/SonosKit/Tests/SonosKitTests/SocketFrameTests.swift`

**Interfaces:**
- Consumes: wire types and mapping from Task 2.
- Produces:
  - `struct SocketHeader: Codable, Hashable, Sendable { namespace, command?, response?, success?, type?, householdId?, groupId?, playerId? }`
  - `public struct Subscription: Hashable, Sendable { namespace: String; scope: Scope }` with `enum Scope { case group(String), player(String), household }` and `func frame(command: String) -> Data`
  - `enum SocketEvent: Hashable, Sendable` with cases `subscribed(namespace:success:)`, `playbackStatus(groupID:state:)`, `metadata(groupID:nowPlaying:)`, `groupVolume(groupID:volume:)`, `playerVolume(playerID:volume:)`, `groups(groups:players:)`, `favoritesChanged`, `globalError(code:)`, `unknown(type:)`
  - `enum SocketFrameDecoder { static func decode(_ data: Data) throws -> SocketEvent }`

- [ ] **Step 1: Write the failing tests**

`Packages/SonosKit/Tests/SonosKitTests/SocketFrameTests.swift`:
```swift
import Foundation
import Testing
@testable import SonosKit

@Suite struct SocketFrameTests {
    @Test func subscribeFrameIsHeaderPlusEmptyBody() throws {
        let data = Subscription(namespace: "playback:1", scope: .group("G1")).frame(command: "subscribe")
        let array = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        #expect(array.count == 2)
        #expect(array[0]["namespace"] as? String == "playback:1")
        #expect(array[0]["command"] as? String == "subscribe")
        #expect(array[0]["groupId"] as? String == "G1")
        #expect(array[0]["playerId"] == nil)
        #expect(array[1].isEmpty)
    }

    @Test func playerAndHouseholdScopesUseTheRightKey() throws {
        let player = try JSONSerialization.jsonObject(with: Subscription(namespace: "playerVolume:1", scope: .player("P1")).frame(command: "subscribe")) as! [[String: Any]]
        #expect(player[0]["playerId"] as? String == "P1")
        let household = try JSONSerialization.jsonObject(with: Subscription(namespace: "groups:1", scope: .household).frame(command: "unsubscribe")) as! [[String: Any]]
        #expect(household[0]["householdId"] as? String == "local")
        #expect(household[0]["command"] as? String == "unsubscribe")
    }

    @Test func decodesTheCapturedEventSequence() throws {
        let events = try Fixtures.lines("events.jsonl").map { try SocketFrameDecoder.decode(Data($0.utf8)) }
        let gid = "RINCON_542A1B73A25001400:620674909"
        #expect(events.count == 13)
        #expect(events[0] == .subscribed(namespace: "playback:1", success: true))
        #expect(events[1] == .playbackStatus(groupID: gid, state: .playing))
        #expect(events[2] == .subscribed(namespace: "playbackMetadata:1", success: true))
        guard case .metadata(let metaGroup, let nowPlaying) = events[3] else { Issue.record("expected metadata"); return }
        #expect(metaGroup == gid)
        #expect(nowPlaying?.title == "Off the Wall")
        #expect(events[5] == .groupVolume(groupID: gid, volume: Volume(level: 5, muted: false, fixed: false)))
        #expect(events[7] == .playerVolume(playerID: "RINCON_542A1B73A25001400", volume: Volume(level: 2, muted: false, fixed: false)))
        guard case .groups(let groups, let players) = events[9] else { Issue.record("expected groups"); return }
        #expect(groups.count == 3)
        #expect(players.count == 4)
        #expect(groups.allSatisfy { $0.playbackState == nil })
        #expect(events[11] == .favoritesChanged)
        #expect(events[12] == .globalError(code: "ERROR_UNSUPPORTED_NAMESPACE"))
    }

    @Test func unknownTypeDoesNotThrow() throws {
        let frame = #"[{"namespace":"playback:1","type":"somethingNew","groupId":"G1"},{"x":1}]"#
        #expect(try SocketFrameDecoder.decode(Data(frame.utf8)) == .unknown(type: "somethingNew"))
    }

    @Test func malformedFrameThrows() {
        #expect(throws: (any Error).self) { try SocketFrameDecoder.decode(Data("not json".utf8)) }
        #expect(throws: (any Error).self) { try SocketFrameDecoder.decode(Data("[]".utf8)) }
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
swift test --filter SocketFrameTests 2>&1 | tail -5
```
Expected: compile errors about `Subscription`, `SocketFrameDecoder`.

- [ ] **Step 3: Write the implementation**

`Packages/SonosKit/Sources/SonosKit/Socket/SocketFrame.swift`:
```swift
import Foundation

/// The first element of every websocket frame the player sends or receives.
struct SocketHeader: Codable, Hashable, Sendable {
    var namespace: String
    var command: String?
    var response: String?
    var success: Bool?
    var type: String?
    var householdId: String?
    var groupId: String?
    var playerId: String?
}

/// A frame is `[header, body]`. Decoding is two-stage: header first, then the body by header type.
struct Frame<Body: Decodable>: Decodable {
    var header: SocketHeader
    var body: Body

    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        header = try container.decode(SocketHeader.self)
        body = try container.decode(Body.self)
    }
}

private struct HeaderOnly: Decodable {
    var header: SocketHeader
    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        header = try container.decode(SocketHeader.self)
    }
}

private struct EmptyBody: Codable {}

public struct Subscription: Hashable, Sendable {
    public enum Scope: Hashable, Sendable {
        case group(String)
        case player(String)
        case household
    }

    public var namespace: String
    public var scope: Scope

    public init(namespace: String, scope: Scope) {
        self.namespace = namespace
        self.scope = scope
    }

    /// `[{"namespace":…,"command":…,<scope key>:…},{}]`
    func frame(command: String) -> Data {
        var header = SocketHeader(namespace: namespace, command: command)
        switch scope {
        case .group(let id): header.groupId = id
        case .player(let id): header.playerId = id
        case .household: header.householdId = "local"
        }
        let encoder = JSONEncoder()
        let headerData = try! encoder.encode(header)
        var data = Data("[".utf8)
        data.append(headerData)
        data.append(Data(",{}]".utf8))
        return data
    }
}

enum SocketEvent: Hashable, Sendable {
    case subscribed(namespace: String, success: Bool)
    case playbackStatus(groupID: String, state: PlaybackState)
    case metadata(groupID: String, nowPlaying: NowPlaying?)
    case groupVolume(groupID: String, volume: Volume)
    case playerVolume(playerID: String, volume: Volume)
    case groups(groups: [WireGroup], players: [WirePlayer])
    case favoritesChanged
    case globalError(code: String)
    case unknown(type: String)
}

enum SocketFrameDecoder {
    static func decode(_ data: Data) throws -> SocketEvent {
        let decoder = JSONDecoder()
        let header = try decoder.decode(HeaderOnly.self, from: data).header
        switch header.type {
        case "playbackStatus":
            let frame = try decoder.decode(Frame<WirePlaybackStatus>.self, from: data)
            return .playbackStatus(groupID: header.groupId ?? "", state: PlaybackState(wireValue: frame.body.playbackState))
        case "metadataStatus":
            let frame = try decoder.decode(Frame<WireMetadataStatus>.self, from: data)
            return .metadata(groupID: header.groupId ?? "", nowPlaying: NowPlaying(wire: frame.body))
        case "groupVolume":
            let frame = try decoder.decode(Frame<WireVolume>.self, from: data)
            return .groupVolume(groupID: header.groupId ?? "", volume: Volume(wire: frame.body))
        case "playerVolume":
            let frame = try decoder.decode(Frame<WireVolume>.self, from: data)
            return .playerVolume(playerID: header.playerId ?? "", volume: Volume(wire: frame.body))
        case "groups":
            let frame = try decoder.decode(Frame<GroupsResponse>.self, from: data)
            return .groups(groups: frame.body.groups, players: frame.body.players)
        case "versionChanged" where header.namespace.hasPrefix("favorites"):
            return .favoritesChanged
        case "globalError":
            let frame = try decoder.decode(Frame<WireGlobalError>.self, from: data)
            return .globalError(code: frame.body.errorCode)
        case "none", nil:
            if let response = header.response {
                _ = response
                return .subscribed(namespace: header.namespace, success: header.success ?? false)
            }
            return .unknown(type: header.type ?? "")
        default:
            return .unknown(type: header.type ?? "")
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
swift test --filter SocketFrameTests 2>&1 | tail -5
```
Expected: `5 tests passed`.

- [ ] **Step 5: Commit**

```bash
git add Packages/SonosKit
git commit -m "feat(sonoskit): decode websocket frames into typed events"
```

---

### Task 4: HouseholdEvent and the pure reducer

**Files:**
- Create: `Packages/SonosKit/Sources/SonosKit/Reducer/HouseholdEvent.swift`
- Create: `Packages/SonosKit/Sources/SonosKit/Reducer/SnapshotReducer.swift`
- Test: `Packages/SonosKit/Tests/SonosKitTests/ReducerTests.swift`

**Interfaces:**
- Consumes: domain and wire types (Task 2).
- Produces:
  - `enum HouseholdEvent: Hashable, Sendable { case status(HouseholdStatus); topology(groups: [WireGroup], players: [WirePlayer]); playbackStatus(groupID:state:); metadata(groupID:nowPlaying:); groupVolume(groupID:volume:); playerVolume(playerID:volume:); favorites([Favorite]); playerHasSub(playerID:hasSub:); playerRemoved(playerID:) }`
  - `enum SnapshotReducer { static func reduce(_ snapshot: HouseholdSnapshot, _ event: HouseholdEvent) -> HouseholdSnapshot }`

Rules the reducer must implement:
1. `topology` rebuilds `groups` and `players` from the wire lists, **preserving** a group's existing `playbackState`, `volume`, and `nowPlaying` when its id is unchanged, and a player's `hasSub`. A wire group with a `playbackState` string overrides the preserved state. New groups default to `.idle` and `Volume.silent`. Groups and players are sorted by name using `localizedStandardCompare`.
2. `playbackStatus`, `metadata`, `groupVolume` update the matching group; unknown group ids are ignored.
3. `playerVolume` writes `playerVolumes[playerID]`.
4. `favorites` replaces the list. `status` replaces the status.
5. `playerHasSub` updates the player. `playerRemoved` removes the player, removes it from every group's `playerIDs`, drops groups left with no players, and removes its volume entry.

- [ ] **Step 1: Write the failing tests**

`Packages/SonosKit/Tests/SonosKitTests/ReducerTests.swift`:
```swift
import Foundation
import Testing
@testable import SonosKit

@Suite struct ReducerTests {
    let gid = "RINCON_542A1B73A25001400:620674909"

    func topology() throws -> HouseholdEvent {
        let response = try JSONDecoder().decode(GroupsResponse.self, from: Fixtures.data("groups.json"))
        return .topology(groups: response.groups, players: response.players)
    }

    @Test func topologyBuildsSortedGroupsAndPlayers() throws {
        let snapshot = SnapshotReducer.reduce(HouseholdSnapshot(), try topology())
        #expect(snapshot.groups.map(\.name) == ["Elsas Sovrum", "Flyttbar + 1", "Sovrum"])
        #expect(snapshot.players.map(\.name) == ["Elsas Sovrum", "Flyttbar", "Sovrum", "Stereo"])
        let flyttbar = try #require(snapshot.group(gid))
        #expect(flyttbar.playbackState == .playing)
        #expect(flyttbar.volume == .silent)
        #expect(flyttbar.nowPlaying == nil)
        #expect(snapshot.player("RINCON_347E5C04E98101400")?.address == "192.168.1.105")
        #expect(snapshot.status == .discovering)
    }

    @Test func topologyWithoutPlaybackStatePreservesKnownState() throws {
        var snapshot = SnapshotReducer.reduce(HouseholdSnapshot(), try topology())
        snapshot = SnapshotReducer.reduce(snapshot, .groupVolume(groupID: gid, volume: Volume(level: 40, muted: true, fixed: false)))
        snapshot = SnapshotReducer.reduce(snapshot, .metadata(groupID: gid, nowPlaying: NowPlaying(title: "Song")))
        snapshot = SnapshotReducer.reduce(snapshot, .playerHasSub(playerID: "RINCON_347E5C04E98101400", hasSub: true))

        // Same groups, but as the websocket sends them: no playbackState.
        let eventGroups = try Fixtures.lines("events.jsonl").compactMap { line -> (groups: [WireGroup], players: [WirePlayer])? in
            if case .groups(let g, let p) = try SocketFrameDecoder.decode(Data(line.utf8)) { return (g, p) }
            return nil
        }.first
        let wire = try #require(eventGroups)
        let next = SnapshotReducer.reduce(snapshot, .topology(groups: wire.groups, players: wire.players))

        let flyttbar = try #require(next.group(gid))
        #expect(flyttbar.playbackState == .playing)
        #expect(flyttbar.volume.level == 40)
        #expect(flyttbar.nowPlaying?.title == "Song")
        #expect(next.player("RINCON_347E5C04E98101400")?.hasSub == true)
    }

    @Test func topologyChangeMovesPlayersAndDropsOldGroups() throws {
        let snapshot = SnapshotReducer.reduce(HouseholdSnapshot(), try topology())
        let regrouped: [WireGroup] = [
            WireGroup(id: "RINCON_542A1B73A25001400:1", name: "Flyttbar", coordinatorId: "RINCON_542A1B73A25001400", playbackState: nil, playerIds: ["RINCON_542A1B73A25001400"]),
            WireGroup(id: "RINCON_347E5C04E98101400:1", name: "Stereo", coordinatorId: "RINCON_347E5C04E98101400", playbackState: "PLAYBACK_STATE_PAUSED", playerIds: ["RINCON_347E5C04E98101400"]),
        ]
        let players = snapshot.players.map { WirePlayer(id: $0.id, name: $0.name, websocketUrl: "wss://\($0.address):1443/websocket/api") }
        let next = SnapshotReducer.reduce(snapshot, .topology(groups: regrouped, players: players))
        #expect(next.groups.map(\.name) == ["Flyttbar", "Stereo"])
        #expect(next.group(gid) == nil)
        #expect(next.group("RINCON_347E5C04E98101400:1")?.playbackState == .paused)
        #expect(next.group("RINCON_542A1B73A25001400:1")?.playbackState == .idle)
        #expect(next.players.count == 4)
    }

    @Test func groupScopedEventsUpdateOnlyTheirGroup() throws {
        var snapshot = SnapshotReducer.reduce(HouseholdSnapshot(), try topology())
        snapshot = SnapshotReducer.reduce(snapshot, .playbackStatus(groupID: gid, state: .paused))
        snapshot = SnapshotReducer.reduce(snapshot, .playbackStatus(groupID: "nope", state: .playing))
        #expect(snapshot.group(gid)?.playbackState == .paused)
        #expect(snapshot.groups.filter { $0.playbackState == .playing }.isEmpty)
    }

    @Test func playerVolumeFavoritesAndStatus() throws {
        var snapshot = SnapshotReducer.reduce(HouseholdSnapshot(), try topology())
        snapshot = SnapshotReducer.reduce(snapshot, .playerVolume(playerID: "RINCON_542A1B73A25001400", volume: Volume(level: 2, muted: false, fixed: false)))
        snapshot = SnapshotReducer.reduce(snapshot, .favorites([Favorite(id: "3", name: "P3")]))
        snapshot = SnapshotReducer.reduce(snapshot, .status(.ready))
        #expect(snapshot.playerVolumes["RINCON_542A1B73A25001400"]?.level == 2)
        #expect(snapshot.favorites.map(\.name) == ["P3"])
        #expect(snapshot.status == .ready)
    }

    @Test func playerRemovedCleansUpEverywhere() throws {
        var snapshot = SnapshotReducer.reduce(HouseholdSnapshot(), try topology())
        snapshot = SnapshotReducer.reduce(snapshot, .playerVolume(playerID: "RINCON_48A6B8194D2A01400", volume: Volume(level: 9, muted: false, fixed: false)))
        snapshot = SnapshotReducer.reduce(snapshot, .playerRemoved(playerID: "RINCON_48A6B8194D2A01400"))
        #expect(snapshot.player("RINCON_48A6B8194D2A01400") == nil)
        #expect(snapshot.groups.map(\.name) == ["Elsas Sovrum", "Flyttbar + 1"])
        #expect(snapshot.playerVolumes["RINCON_48A6B8194D2A01400"] == nil)

        snapshot = SnapshotReducer.reduce(snapshot, .playerRemoved(playerID: "RINCON_347E5C04E98101400"))
        #expect(snapshot.group(gid)?.playerIDs == ["RINCON_542A1B73A25001400"])
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
swift test --filter ReducerTests 2>&1 | tail -5
```
Expected: compile errors about `HouseholdEvent` and `SnapshotReducer`.

- [ ] **Step 3: Write the implementation**

`Packages/SonosKit/Sources/SonosKit/Reducer/HouseholdEvent.swift`:
```swift
import Foundation

/// Every fact that can change the household snapshot. Produced by REST results,
/// websocket events, discovery, and EQ probing. Consumed only by `SnapshotReducer`.
enum HouseholdEvent: Hashable, Sendable {
    case status(HouseholdStatus)
    case topology(groups: [WireGroup], players: [WirePlayer])
    case playbackStatus(groupID: String, state: PlaybackState)
    case metadata(groupID: String, nowPlaying: NowPlaying?)
    case groupVolume(groupID: String, volume: Volume)
    case playerVolume(playerID: String, volume: Volume)
    case favorites([Favorite])
    case playerHasSub(playerID: String, hasSub: Bool)
    case playerRemoved(playerID: String)
}
```

`Packages/SonosKit/Sources/SonosKit/Reducer/SnapshotReducer.swift`:
```swift
import Foundation

enum SnapshotReducer {
    static func reduce(_ snapshot: HouseholdSnapshot, _ event: HouseholdEvent) -> HouseholdSnapshot {
        var next = snapshot
        switch event {
        case .status(let status):
            next.status = status

        case .topology(let wireGroups, let wirePlayers):
            let oldGroups = Dictionary(snapshot.groups.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let oldPlayers = Dictionary(snapshot.players.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            next.groups = wireGroups.map { wire in
                let old = oldGroups[wire.id]
                return Group(
                    id: wire.id,
                    name: wire.name,
                    coordinatorID: wire.coordinatorId,
                    playerIDs: wire.playerIds,
                    playbackState: wire.playbackState.map(PlaybackState.init(wireValue:)) ?? old?.playbackState ?? .idle,
                    volume: old?.volume ?? .silent,
                    nowPlaying: old?.nowPlaying
                )
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            next.players = wirePlayers
                .map { Player(wire: $0, hasSub: oldPlayers[$0.id]?.hasSub ?? false) }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        case .playbackStatus(let groupID, let state):
            update(&next, groupID) { $0.playbackState = state }

        case .metadata(let groupID, let nowPlaying):
            update(&next, groupID) { $0.nowPlaying = nowPlaying }

        case .groupVolume(let groupID, let volume):
            update(&next, groupID) { $0.volume = volume }

        case .playerVolume(let playerID, let volume):
            next.playerVolumes[playerID] = volume

        case .favorites(let favorites):
            next.favorites = favorites

        case .playerHasSub(let playerID, let hasSub):
            if let index = next.players.firstIndex(where: { $0.id == playerID }) {
                next.players[index].hasSub = hasSub
            }

        case .playerRemoved(let playerID):
            next.players.removeAll { $0.id == playerID }
            next.playerVolumes[playerID] = nil
            next.groups = next.groups.compactMap { group in
                var group = group
                group.playerIDs.removeAll { $0 == playerID }
                return group.playerIDs.isEmpty ? nil : group
            }
        }
        return next
    }

    private static func update(_ snapshot: inout HouseholdSnapshot, _ groupID: String, _ change: (inout Group) -> Void) {
        guard let index = snapshot.groups.firstIndex(where: { $0.id == groupID }) else { return }
        change(&snapshot.groups[index])
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
swift test --filter ReducerTests 2>&1 | tail -5
```
Expected: `6 tests passed`.

- [ ] **Step 5: Commit**

```bash
git add Packages/SonosKit
git commit -m "feat(sonoskit): add pure snapshot reducer"
```

---

### Task 5: Transport protocols, trust policy, URLSession transport

**Files:**
- Create: `Packages/SonosKit/Sources/SonosKit/Transport/Transport.swift`
- Create: `Packages/SonosKit/Sources/SonosKit/Transport/TrustPolicy.swift`
- Create: `Packages/SonosKit/Sources/SonosKit/Transport/URLSessionTransport.swift`
- Create: `Packages/SonosKit/Tests/SonosKitTests/Support/FakeSocketConnection.swift`
- Create: `Packages/SonosKit/Tests/SonosKitTests/Support/FakeTransport.swift`
- Create: `Packages/SonosKit/Tests/SonosKitTests/Support/Wait.swift`
- Test: `Packages/SonosKit/Tests/SonosKitTests/TrustPolicyTests.swift`

**Interfaces:**
- Produces: `APIRequest`, `APIResponse`, `Transport`, `SocketConnection` (see the interfaces block at the top), `enum TrustPolicy { static func isPrivateIPv4(_ host: String) -> Bool }`, `public final class TrustStore: Sendable { func allow(host:); func shouldTrust(host:) -> Bool }`, `public final class URLSessionTransport: Transport { public let trustStore: TrustStore; public init() }`.
- Test support produced for later tasks: `FakeTransport` (records `requests`, `respond(whenPathContains:status:body:)`, `respond(whenPathContains:sequence:)`, `sockets`, `socketCount`), `FakeSocketConnection` (`sent`, `push(_:)`, `fail(_:)`, `close()`), `waitUntil(_:timeout:)`.

- [ ] **Step 1: Write the failing trust tests**

`Packages/SonosKit/Tests/SonosKitTests/TrustPolicyTests.swift`:
```swift
import Testing
@testable import SonosKit

@Suite struct TrustPolicyTests {
    @Test func privateRangesAreRecognised() {
        #expect(TrustPolicy.isPrivateIPv4("192.168.1.105"))
        #expect(TrustPolicy.isPrivateIPv4("10.0.0.7"))
        #expect(TrustPolicy.isPrivateIPv4("172.16.0.1"))
        #expect(TrustPolicy.isPrivateIPv4("172.31.255.254"))
        #expect(!TrustPolicy.isPrivateIPv4("172.32.0.1"))
        #expect(!TrustPolicy.isPrivateIPv4("8.8.8.8"))
        #expect(!TrustPolicy.isPrivateIPv4("sonos.com"))
        #expect(!TrustPolicy.isPrivateIPv4("192.168.1"))
        #expect(!TrustPolicy.isPrivateIPv4("192.168.1.300"))
    }

    @Test func storeTrustsOnlyAllowedPrivateHosts() {
        let store = TrustStore()
        #expect(!store.shouldTrust(host: "192.168.1.105"))
        store.allow(host: "192.168.1.105")
        store.allow(host: "8.8.8.8")
        #expect(store.shouldTrust(host: "192.168.1.105"))
        #expect(!store.shouldTrust(host: "8.8.8.8"))
        #expect(!store.shouldTrust(host: "192.168.1.28"))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
swift test --filter TrustPolicyTests 2>&1 | tail -5
```
Expected: compile errors about `TrustPolicy`, `TrustStore`.

- [ ] **Step 3: Write the protocols and trust policy**

`Packages/SonosKit/Sources/SonosKit/Transport/Transport.swift`:
```swift
import Foundation

public struct APIRequest: Sendable, Hashable {
    public var method: String
    public var url: URL
    public var headers: [String: String]
    public var body: Data?

    public init(method: String, url: URL, headers: [String: String] = [:], body: Data? = nil) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
    }
}

public struct APIResponse: Sendable {
    public var status: Int
    public var body: Data

    public init(status: Int, body: Data) {
        self.status = status
        self.body = body
    }
}

/// One open websocket. `messages()` ends (or throws) when the connection drops.
public protocol SocketConnection: Sendable {
    func send(_ data: Data) async throws
    func messages() -> AsyncThrowingStream<Data, any Error>
    func ping() async throws
    func close()
}

/// Everything that touches the network goes through this so tests can fake it.
public protocol Transport: Sendable {
    func send(_ request: APIRequest) async throws -> APIResponse
    func openSocket(_ url: URL, headers: [String: String], protocols: [String]) async throws -> any SocketConnection
}
```

`Packages/SonosKit/Sources/SonosKit/Transport/TrustPolicy.swift`:
```swift
import Foundation
import Synchronization

public enum TrustPolicy {
    /// 10/8, 172.16/12, 192.168/16. Hostnames and public addresses are never private.
    public static func isPrivateIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        let octets = parts.compactMap { UInt8($0) }
        guard octets.count == 4 else { return false }
        switch (octets[0], octets[1]) {
        case (10, _): return true
        case (172, 16...31): return true
        case (192, 168): return true
        default: return false
        }
    }
}

/// Hosts discovered on the LAN whose self-signed certificate we accept.
public final class TrustStore: Sendable {
    private let hosts = Mutex<Set<String>>([])

    public init() {}

    public func allow(host: String) {
        hosts.withLock { $0.insert(host) }
    }

    public func shouldTrust(host: String) -> Bool {
        TrustPolicy.isPrivateIPv4(host) && hosts.withLock { $0.contains(host) }
    }
}
```

- [ ] **Step 4: Run the trust tests to verify they pass**

```bash
swift test --filter TrustPolicyTests 2>&1 | tail -5
```
Expected: `2 tests passed`.

- [ ] **Step 5: Write the real transport (compiles, exercised by sonosctl in Task 12)**

`Packages/SonosKit/Sources/SonosKit/Transport/URLSessionTransport.swift`:
```swift
import Foundation

public final class URLSessionTransport: Transport, @unchecked Sendable {
    public let trustStore: TrustStore
    private let session: URLSession

    public init(trustStore: TrustStore = TrustStore()) {
        self.trustStore = trustStore
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.httpShouldUsePipelining = false
        session = URLSession(configuration: configuration, delegate: TrustDelegate(store: trustStore), delegateQueue: nil)
    }

    public func send(_ request: APIRequest) async throws -> APIResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        let (data, response) = try await session.data(for: urlRequest)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return APIResponse(status: status, body: data)
    }

    public func openSocket(_ url: URL, headers: [String: String], protocols: [String]) async throws -> any SocketConnection {
        var request = URLRequest(url: url)
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.setValue(protocols.joined(separator: ", "), forHTTPHeaderField: "Sec-WebSocket-Protocol")
        let task = session.webSocketTask(with: request)
        task.resume()
        return URLSessionSocketConnection(task: task)
    }
}

/// Accepts the player's self-signed certificate only for allowed private hosts.
private final class TrustDelegate: NSObject, URLSessionDelegate, Sendable {
    let store: TrustStore

    init(store: TrustStore) {
        self.store = store
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let space = challenge.protectionSpace
        guard space.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = space.serverTrust,
              store.shouldTrust(host: space.host) else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}

private final class URLSessionSocketConnection: SocketConnection, @unchecked Sendable {
    private let task: URLSessionWebSocketTask

    init(task: URLSessionWebSocketTask) {
        self.task = task
    }

    func send(_ data: Data) async throws {
        try await task.send(.string(String(decoding: data, as: UTF8.self)))
    }

    func messages() -> AsyncThrowingStream<Data, any Error> {
        let task = self.task
        return AsyncThrowingStream { continuation in
            let receiver = Task {
                do {
                    while !Task.isCancelled {
                        switch try await task.receive() {
                        case .string(let text): continuation.yield(Data(text.utf8))
                        case .data(let data): continuation.yield(data)
                        @unknown default: break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in receiver.cancel() }
        }
    }

    func ping() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            task.sendPing { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }

    func close() {
        task.cancel(with: .normalClosure, reason: nil)
    }
}
```

- [ ] **Step 6: Write the test doubles for later tasks**

`Packages/SonosKit/Tests/SonosKitTests/Support/FakeSocketConnection.swift`:
```swift
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
```

`Packages/SonosKit/Tests/SonosKitTests/Support/FakeTransport.swift`:
```swift
import Foundation
import Synchronization
@testable import SonosKit

struct StubResponse: Sendable {
    var status: Int = 200
    var body: Data = Data("{}".utf8)
}

/// Records every request, answers from stubs matched by URL fragment (last registered wins),
/// and hands out FakeSocketConnections that tests can push frames into.
final class FakeTransport: Transport, Sendable {
    private struct Rule: Sendable {
        var fragment: String
        var sequence: [StubResponse]
        var index: Int = 0
    }

    private struct State: Sendable {
        var requests: [APIRequest] = []
        var rules: [Rule] = []
        var sockets: [FakeSocketConnection] = []
    }

    private let state = Mutex(State())

    var requests: [APIRequest] { state.withLock { $0.requests } }
    var sockets: [FakeSocketConnection] { state.withLock { $0.sockets } }
    var socketCount: Int { sockets.count }

    func requests(matching fragment: String) -> [APIRequest] {
        requests.filter { $0.url.absoluteString.contains(fragment) }
    }

    func socket(forHost host: String) -> FakeSocketConnection? {
        sockets.last { $0.url.host() == host }
    }

    func respond(whenPathContains fragment: String, status: Int = 200, body: Data = Data("{}".utf8)) {
        respond(whenPathContains: fragment, sequence: [StubResponse(status: status, body: body)])
    }

    /// Answers in order; the last stub repeats forever.
    func respond(whenPathContains fragment: String, sequence: [StubResponse]) {
        state.withLock { $0.rules.append(Rule(fragment: fragment, sequence: sequence)) }
    }

    func send(_ request: APIRequest) async throws -> APIResponse {
        let stub: StubResponse = state.withLock { state in
            state.requests.append(request)
            guard let ruleIndex = state.rules.lastIndex(where: { request.url.absoluteString.contains($0.fragment) }) else {
                return StubResponse()
            }
            var rule = state.rules[ruleIndex]
            let response = rule.sequence[min(rule.index, rule.sequence.count - 1)]
            rule.index += 1
            state.rules[ruleIndex] = rule
            return response
        }
        return APIResponse(status: stub.status, body: stub.body)
    }

    func openSocket(_ url: URL, headers: [String: String], protocols: [String]) async throws -> any SocketConnection {
        let connection = FakeSocketConnection(url: url)
        state.withLock { $0.sockets.append(connection) }
        return connection
    }
}
```

`Packages/SonosKit/Tests/SonosKitTests/Support/Wait.swift`:
```swift
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
```

- [ ] **Step 7: Build everything and run all tests**

```bash
swift build 2>&1 | tail -3 && swift test 2>&1 | tail -3
```
Expected: build succeeds, all tests so far pass (22). If `Mutex` is unavailable, confirm `import Synchronization` and the `platforms: [.macOS("15.0")]` line.

- [ ] **Step 8: Commit**

```bash
git add Packages/SonosKit
git commit -m "feat(sonoskit): add transport protocols, trust policy and URLSession transport"
```

---
### Task 6: LocalAPIClient and error mapping

**Files:**
- Create: `Packages/SonosKit/Sources/SonosKit/LocalAPI/LocalAPIError.swift`
- Create: `Packages/SonosKit/Sources/SonosKit/LocalAPI/LocalAPIClient.swift`
- Test: `Packages/SonosKit/Tests/SonosKitTests/LocalAPIClientTests.swift`

**Interfaces:**
- Consumes: `Transport`, `APIRequest`, `APIResponse` (Task 5); wire types (Task 2); `FakeTransport`.
- Produces:
  - `public enum LocalAPIError: Error, Hashable, Sendable { case invalidAPIKey, unauthorized, coordinatorMoved(newCoordinatorID: String?), groupGone, http(status: Int), decoding(String) }` with `static func from(status: Int, body: Data) -> LocalAPIError`
  - `public struct LocalAPIClient: Sendable` with `static let apiKey`, `init(transport:)`, and: `groups(from address:) -> GroupsResponse`, `favorites(from address:) -> [Favorite]`, `play(groupID:at:)`, `pause`, `next`, `previous`, `setGroupVolume(_:groupID:at:)`, `setGroupMuted(_:groupID:at:)`, `setPlayerVolume(_:playerID:at:)`, `setPlayerMuted(_:playerID:at:)`, `loadFavorite(_:groupID:at:)`, `setGroupMembers(_:groupID:at:)`. All `async throws`.

- [ ] **Step 1: Write the failing tests**

`Packages/SonosKit/Tests/SonosKitTests/LocalAPIClientTests.swift`:
```swift
import Foundation
import Testing
@testable import SonosKit

@Suite struct LocalAPIClientTests {
    let transport = FakeTransport()
    var client: LocalAPIClient { LocalAPIClient(transport: transport) }
    let gid = "RINCON_542A1B73A25001400:620674909"

    @Test func getGroupsBuildsTheRightRequest() async throws {
        transport.respond(whenPathContains: "/households/local/groups", body: Fixtures.data("groups.json"))
        let response = try await client.groups(from: "192.168.1.105")
        #expect(response.groups.count == 3)
        let request = try #require(transport.requests.first)
        #expect(request.method == "GET")
        #expect(request.url.absoluteString == "https://192.168.1.105:1443/api/v1/households/local/groups")
        #expect(request.headers["X-Sonos-Api-Key"] == "123e4567-e89b-12d3-a456-426655440000")
        #expect(request.body == nil)
    }

    @Test func favoritesAreMapped() async throws {
        transport.respond(whenPathContains: "/favorites", body: Fixtures.data("favorites.json"))
        let favorites = try await client.favorites(from: "192.168.1.216")
        #expect(favorites.map(\.name) == ["P3"])
    }

    @Test func transportCommandsPostToCoordinatorPaths() async throws {
        try await client.play(groupID: gid, at: "192.168.1.216")
        try await client.pause(groupID: gid, at: "192.168.1.216")
        try await client.next(groupID: gid, at: "192.168.1.216")
        try await client.previous(groupID: gid, at: "192.168.1.216")
        let paths = transport.requests.map { $0.url.path() }
        #expect(paths == [
            "/api/v1/groups/\(gid)/playback/play",
            "/api/v1/groups/\(gid)/playback/pause",
            "/api/v1/groups/\(gid)/playback/skipToNextTrack",
            "/api/v1/groups/\(gid)/playback/skipToPreviousTrack",
        ])
        #expect(transport.requests.allSatisfy { $0.method == "POST" })
    }

    @Test func volumeMuteFavoriteAndMembersSendJSONBodies() async throws {
        try await client.setGroupVolume(13, groupID: gid, at: "192.168.1.216")
        try await client.setGroupMuted(true, groupID: gid, at: "192.168.1.216")
        try await client.setPlayerVolume(20, playerID: "P1", at: "192.168.1.105")
        try await client.setPlayerMuted(false, playerID: "P1", at: "192.168.1.105")
        try await client.loadFavorite("3", groupID: gid, at: "192.168.1.216")
        try await client.setGroupMembers(["P1", "P2"], groupID: gid, at: "192.168.1.216")

        let requests = transport.requests
        #expect(requests.map { $0.url.path() } == [
            "/api/v1/groups/\(gid)/groupVolume",
            "/api/v1/groups/\(gid)/groupVolume/mute",
            "/api/v1/players/P1/playerVolume",
            "/api/v1/players/P1/playerVolume/mute",
            "/api/v1/groups/\(gid)/favorites",
            "/api/v1/groups/\(gid)/groups/setGroupMembers",
        ])
        func json(_ i: Int) throws -> [String: Any] {
            let body = try #require(requests[i].body)
            return try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        }
        #expect(try json(0)["volume"] as? Int == 13)
        #expect(try json(1)["muted"] as? Bool == true)
        #expect(try json(2)["volume"] as? Int == 20)
        #expect(try json(3)["muted"] as? Bool == false)
        #expect(try json(4)["favoriteId"] as? String == "3")
        #expect(try json(4)["playOnCompletion"] as? Bool == true)
        #expect(try json(5)["playerIds"] as? [String] == ["P1", "P2"])
        #expect(requests.allSatisfy { $0.headers["Content-Type"] == "application/json" })
    }

    @Test func errorBodiesBecomeTypedErrors() {
        #expect(LocalAPIError.from(status: 400, body: Fixtures.data("error_400_nokey.json")) == .invalidAPIKey)
        #expect(LocalAPIError.from(status: 404, body: Fixtures.data("error_404_coordinator_moved.json")) == .coordinatorMoved(newCoordinatorID: "RINCON_542A1B73A25001400"))
        #expect(LocalAPIError.from(status: 404, body: Fixtures.data("error_unknown_group.json")) == .groupGone)
        let notAuthorized = Data(#"{"_objectType":"globalError","errorCode":"ERROR_NOT_AUTHORIZED"}"#.utf8)
        #expect(LocalAPIError.from(status: 401, body: notAuthorized) == .unauthorized)
        #expect(LocalAPIError.from(status: 401, body: Data()) == .unauthorized)
        #expect(LocalAPIError.from(status: 500, body: Data("oops".utf8)) == .http(status: 500))
    }

    @Test func nonSuccessResponsesThrow() async {
        transport.respond(whenPathContains: "/playback/play", status: 404, body: Fixtures.data("error_404_coordinator_moved.json"))
        await #expect(throws: LocalAPIError.coordinatorMoved(newCoordinatorID: "RINCON_542A1B73A25001400")) {
            try await client.play(groupID: gid, at: "192.168.1.105")
        }
    }

    @Test func undecodableBodyThrowsDecodingError() async {
        transport.respond(whenPathContains: "/groups", body: Data("<html>".utf8))
        await #expect(throws: LocalAPIError.self) {
            _ = try await client.groups(from: "192.168.1.105")
        }
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
swift test --filter LocalAPIClientTests 2>&1 | tail -5
```
Expected: compile errors about `LocalAPIClient`, `LocalAPIError`.

- [ ] **Step 3: Write the error type**

`Packages/SonosKit/Sources/SonosKit/LocalAPI/LocalAPIError.swift`:
```swift
import Foundation

public enum LocalAPIError: Error, Hashable, Sendable {
    /// The placeholder key was rejected (HTTP 400, ERROR_API_KEY_VALIDATION_FAILED).
    case invalidAPIKey
    /// "Authentication" is switched on in the Sonos app (HTTP 401 / ERROR_NOT_AUTHORIZED).
    case unauthorized
    /// The call went to a player that is no longer the group's coordinator.
    case coordinatorMoved(newCoordinatorID: String?)
    /// The group id no longer exists.
    case groupGone
    case http(status: Int)
    case decoding(String)

    static func from(status: Int, body: Data) -> LocalAPIError {
        let decoder = JSONDecoder()
        if let typed = try? decoder.decode(WireObjectType.self, from: body) {
            switch typed.objectType {
            case "groupCoordinatorChanged":
                if let changed = try? decoder.decode(WireCoordinatorChanged.self, from: body) {
                    return changed.groupStatus == "GROUP_STATUS_GONE" ? .groupGone : .coordinatorMoved(newCoordinatorID: changed.playerId)
                }
            case "globalError":
                if let error = try? decoder.decode(WireGlobalError.self, from: body) {
                    if error.errorCode == "ERROR_API_KEY_VALIDATION_FAILED" { return .invalidAPIKey }
                    if error.errorCode == "ERROR_NOT_AUTHORIZED" { return .unauthorized }
                }
            default:
                break
            }
        }
        if status == 401 { return .unauthorized }
        return .http(status: status)
    }
}
```

- [ ] **Step 4: Write the client**

`Packages/SonosKit/Sources/SonosKit/LocalAPI/LocalAPIClient.swift`:
```swift
import Foundation

/// REST calls to the local Control API on port 1443. Group-scoped calls must be sent to the
/// group's coordinator address; the caller (Household) is responsible for picking it.
public struct LocalAPIClient: Sendable {
    public static let apiKey = "123e4567-e89b-12d3-a456-426655440000"
    public static let port = 1443

    private let transport: any Transport

    public init(transport: any Transport) {
        self.transport = transport
    }

    // MARK: Reads

    func groups(from address: String) async throws -> GroupsResponse {
        try await get(GroupsResponse.self, address: address, path: "/households/local/groups")
    }

    public func favorites(from address: String) async throws -> [Favorite] {
        try await get(WireFavoritesList.self, address: address, path: "/households/local/favorites").items.map(Favorite.init(wire:))
    }

    // MARK: Group commands (send to the coordinator)

    public func play(groupID: String, at address: String) async throws {
        try await post(address: address, path: "/groups/\(groupID)/playback/play")
    }

    public func pause(groupID: String, at address: String) async throws {
        try await post(address: address, path: "/groups/\(groupID)/playback/pause")
    }

    public func next(groupID: String, at address: String) async throws {
        try await post(address: address, path: "/groups/\(groupID)/playback/skipToNextTrack")
    }

    public func previous(groupID: String, at address: String) async throws {
        try await post(address: address, path: "/groups/\(groupID)/playback/skipToPreviousTrack")
    }

    public func setGroupVolume(_ level: Int, groupID: String, at address: String) async throws {
        try await post(address: address, path: "/groups/\(groupID)/groupVolume", body: VolumeBody(volume: level))
    }

    public func setGroupMuted(_ muted: Bool, groupID: String, at address: String) async throws {
        try await post(address: address, path: "/groups/\(groupID)/groupVolume/mute", body: MutedBody(muted: muted))
    }

    public func loadFavorite(_ favoriteID: String, groupID: String, at address: String) async throws {
        try await post(address: address, path: "/groups/\(groupID)/favorites", body: FavoriteBody(favoriteId: favoriteID, playOnCompletion: true))
    }

    public func setGroupMembers(_ playerIDs: [String], groupID: String, at address: String) async throws {
        try await post(address: address, path: "/groups/\(groupID)/groups/setGroupMembers", body: MembersBody(playerIds: playerIDs))
    }

    // MARK: Player commands (send to that player)

    public func setPlayerVolume(_ level: Int, playerID: String, at address: String) async throws {
        try await post(address: address, path: "/players/\(playerID)/playerVolume", body: VolumeBody(volume: level))
    }

    public func setPlayerMuted(_ muted: Bool, playerID: String, at address: String) async throws {
        try await post(address: address, path: "/players/\(playerID)/playerVolume/mute", body: MutedBody(muted: muted))
    }

    // MARK: Plumbing

    private struct VolumeBody: Encodable { var volume: Int }
    private struct MutedBody: Encodable { var muted: Bool }
    private struct FavoriteBody: Encodable { var favoriteId: String; var playOnCompletion: Bool }
    private struct MembersBody: Encodable { var playerIds: [String] }

    func makeRequest(method: String, address: String, path: String, body: Data? = nil) -> APIRequest {
        var headers = ["X-Sonos-Api-Key": Self.apiKey]
        if body != nil { headers["Content-Type"] = "application/json" }
        guard let url = URL(string: "https://\(address):\(Self.port)/api/v1\(path)") else {
            preconditionFailure("Bad local API URL for \(address) \(path)")
        }
        return APIRequest(method: method, url: url, headers: headers, body: body)
    }

    private func perform(_ request: APIRequest) async throws -> Data {
        let response = try await transport.send(request)
        guard (200..<300).contains(response.status) else {
            throw LocalAPIError.from(status: response.status, body: response.body)
        }
        return response.body
    }

    private func get<T: Decodable>(_ type: T.Type, address: String, path: String) async throws -> T {
        let data = try await perform(makeRequest(method: "GET", address: address, path: path))
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw LocalAPIError.decoding("\(path): \(error)")
        }
    }

    private func post(address: String, path: String) async throws {
        _ = try await perform(makeRequest(method: "POST", address: address, path: path))
    }

    private func post<Body: Encodable>(address: String, path: String, body: Body) async throws {
        let data = try JSONEncoder().encode(body)
        _ = try await perform(makeRequest(method: "POST", address: address, path: path, body: data))
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
swift test --filter LocalAPIClientTests 2>&1 | tail -5
```
Expected: `7 tests passed`. If `URL.path()` is flagged, use `url.path` (the property) in the tests.

- [ ] **Step 6: Commit**

```bash
git add Packages/SonosKit
git commit -m "feat(sonoskit): add local API client with typed errors"
```

---

### Task 7: Backoff and PlayerSocket

**Files:**
- Create: `Packages/SonosKit/Sources/SonosKit/Socket/Backoff.swift`
- Create: `Packages/SonosKit/Sources/SonosKit/Socket/PlayerSocket.swift`
- Test: `Packages/SonosKit/Tests/SonosKitTests/BackoffTests.swift`
- Test: `Packages/SonosKit/Tests/SonosKitTests/PlayerSocketTests.swift`

**Interfaces:**
- Consumes: `Transport`, `SocketConnection`, `Subscription`, `SocketEvent`, `SocketFrameDecoder`, `LocalAPIClient.apiKey`, `FakeTransport`, `FakeSocketConnection`, `waitUntil`.
- Produces:
  - `public struct Backoff: Sendable { base: Duration = 1s; max: Duration = 60s; jitter: Double = 0.25; func delay(attempt: Int, random: Double) -> Duration }`
  - `actor PlayerSocket { enum Output: Hashable, Sendable { case connected, disconnected, event(SocketEvent) }; init(playerID: String, address: String, transport: any Transport, backoff: Backoff = Backoff()); let outputs: AsyncStream<Output>; func start(); func stop(); func setSubscriptions(_ desired: Set<Subscription>) async }`

Behaviour: on `start`, loop forever until `stop`: open a socket to `wss://{address}:1443/websocket/api` with the API key header and subprotocol `v1.api.smartspeaker.audio`; send a `subscribe` frame for every desired subscription; yield `.connected`; decode every incoming frame and yield `.event`; when the stream ends or throws, yield `.disconnected`, sleep `backoff.delay(attempt:)`, retry. A successful connection resets the attempt counter. `setSubscriptions` while connected sends `unsubscribe` for dropped and `subscribe` for added subscriptions. A ping is sent every 30 seconds while connected.

- [ ] **Step 1: Write the failing backoff test**

`Packages/SonosKit/Tests/SonosKitTests/BackoffTests.swift`:
```swift
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
```

- [ ] **Step 2: Run it to verify it fails, then implement**

```bash
swift test --filter BackoffTests 2>&1 | tail -3
```
Expected: `cannot find 'Backoff'`.

`Packages/SonosKit/Sources/SonosKit/Socket/Backoff.swift`:
```swift
import Foundation

/// Exponential reconnect delay: base · 2^attempt, capped at `max`, plus up to `jitter` fraction extra.
public struct Backoff: Sendable {
    public var base: Duration
    public var max: Duration
    public var jitter: Double

    public init(base: Duration = .seconds(1), max: Duration = .seconds(60), jitter: Double = 0.25) {
        self.base = base
        self.max = max
        self.jitter = jitter
    }

    /// `random` must be in 0...1; pass `Double.random(in: 0...1)` in production.
    public func delay(attempt: Int, random: Double) -> Duration {
        let exponent = Swift.min(Swift.max(attempt, 0), 30)
        let raw = base * (1 << exponent)
        let capped = raw < max ? raw : max
        let jitterThousandths = Int((random * jitter * 1000).rounded())
        return capped + (capped * jitterThousandths) / 1000
    }
}
```

```bash
swift test --filter BackoffTests 2>&1 | tail -3
```
Expected: `2 tests passed`.

- [ ] **Step 3: Write the failing PlayerSocket tests**

`Packages/SonosKit/Tests/SonosKitTests/PlayerSocketTests.swift`:
```swift
import Foundation
import Testing
@testable import SonosKit

@Suite struct PlayerSocketTests {
    let fastBackoff = Backoff(base: .milliseconds(1), max: .milliseconds(5), jitter: 0)

    @Test func connectsSubscribesAndDecodesEvents() async throws {
        let transport = FakeTransport()
        let socket = PlayerSocket(playerID: "P1", address: "192.168.1.216", transport: transport, backoff: fastBackoff)
        await socket.setSubscriptions([Subscription(namespace: "groupVolume:1", scope: .group("G1"))])
        await socket.start()
        var outputs = socket.outputs.makeAsyncIterator()

        #expect(await outputs.next() == .connected)
        let connection = try #require(transport.socket(forHost: "192.168.1.216"))
        #expect(connection.url.absoluteString == "wss://192.168.1.216:1443/websocket/api")
        #expect(connection.sentText.count == 1)
        #expect(connection.sentText[0].contains(#""command":"subscribe""#))
        #expect(connection.sentText[0].contains(#""namespace":"groupVolume:1""#))

        connection.push(#"[{"namespace":"groupVolume:1","type":"groupVolume","groupId":"G1"},{"volume":7,"muted":false,"fixed":false}]"#)
        #expect(await outputs.next() == .event(.groupVolume(groupID: "G1", volume: Volume(level: 7, muted: false, fixed: false))))

        await socket.stop()
    }

    @Test func reconnectsAfterTheConnectionDrops() async throws {
        let transport = FakeTransport()
        let socket = PlayerSocket(playerID: "P1", address: "192.168.1.216", transport: transport, backoff: fastBackoff)
        await socket.setSubscriptions([Subscription(namespace: "playback:1", scope: .group("G1"))])
        await socket.start()
        var outputs = socket.outputs.makeAsyncIterator()

        #expect(await outputs.next() == .connected)
        transport.sockets[0].fail(URLError(.networkConnectionLost))
        #expect(await outputs.next() == .disconnected)
        #expect(await outputs.next() == .connected)
        #expect(transport.socketCount == 2)
        #expect(transport.sockets[1].sentText.count == 1)

        await socket.stop()
    }

    @Test func changingSubscriptionsSendsUnsubscribeAndSubscribe() async throws {
        let transport = FakeTransport()
        let socket = PlayerSocket(playerID: "P1", address: "192.168.1.216", transport: transport, backoff: fastBackoff)
        let volume = Subscription(namespace: "playerVolume:1", scope: .player("P1"))
        let playback = Subscription(namespace: "playback:1", scope: .group("G1"))
        await socket.setSubscriptions([volume, playback])
        await socket.start()
        var outputs = socket.outputs.makeAsyncIterator()
        #expect(await outputs.next() == .connected)
        let connection = transport.sockets[0]
        #expect(connection.sentText.count == 2)

        await socket.setSubscriptions([volume])
        try await waitUntil { connection.sentText.count == 3 }
        #expect(connection.sentText[2].contains(#""command":"unsubscribe""#))
        #expect(connection.sentText[2].contains(#""groupId":"G1""#))

        await socket.setSubscriptions([volume, Subscription(namespace: "groupVolume:1", scope: .group("G2"))])
        try await waitUntil { connection.sentText.count == 4 }
        #expect(connection.sentText[3].contains(#""command":"subscribe""#))
        #expect(connection.sentText[3].contains(#""groupId":"G2""#))

        await socket.stop()
    }

    @Test func stopEndsTheOutputStream() async throws {
        let transport = FakeTransport()
        let socket = PlayerSocket(playerID: "P1", address: "192.168.1.216", transport: transport, backoff: fastBackoff)
        await socket.start()
        var outputs = socket.outputs.makeAsyncIterator()
        #expect(await outputs.next() == .connected)
        await socket.stop()
        var sawEnd = false
        while let output = await outputs.next() {
            if output == .disconnected { sawEnd = true }
        }
        #expect(sawEnd)
    }
}
```

- [ ] **Step 4: Run them to verify they fail**

```bash
swift test --filter PlayerSocketTests 2>&1 | tail -3
```
Expected: `cannot find 'PlayerSocket'`.

- [ ] **Step 5: Write PlayerSocket**

`Packages/SonosKit/Sources/SonosKit/Socket/PlayerSocket.swift`:
```swift
import Foundation

/// One websocket to one player. Reconnects forever with backoff until `stop()`.
/// Subscriptions are re-sent on every (re)connect.
actor PlayerSocket {
    enum Output: Hashable, Sendable {
        case connected
        case disconnected
        case event(SocketEvent)
    }

    static let subprotocol = "v1.api.smartspeaker.audio"
    static let pingInterval: Duration = .seconds(30)

    let playerID: String
    let url: URL
    nonisolated let outputs: AsyncStream<Output>

    private let transport: any Transport
    private let backoff: Backoff
    private let continuation: AsyncStream<Output>.Continuation
    private var desired: Set<Subscription> = []
    private var active: Set<Subscription> = []
    private var connection: (any SocketConnection)?
    private var runTask: Task<Void, Never>?
    private var stopped = false

    init(playerID: String, address: String, transport: any Transport, backoff: Backoff = Backoff()) {
        self.playerID = playerID
        self.url = URL(string: "wss://\(address):\(LocalAPIClient.port)/websocket/api")!
        self.transport = transport
        self.backoff = backoff
        (outputs, continuation) = AsyncStream<Output>.makeStream()
    }

    func start() {
        guard runTask == nil, !stopped else { return }
        runTask = Task { await run() }
    }

    func stop() {
        stopped = true
        runTask?.cancel()
        runTask = nil
        connection?.close()
        connection = nil
        continuation.yield(.disconnected)
        continuation.finish()
    }

    func setSubscriptions(_ new: Set<Subscription>) async {
        desired = new
        guard let connection else { return }
        for subscription in active.subtracting(new) {
            try? await connection.send(subscription.frame(command: "unsubscribe"))
        }
        for subscription in new.subtracting(active) {
            try? await connection.send(subscription.frame(command: "subscribe"))
        }
        active = new
    }

    private func run() async {
        var attempt = 0
        while !Task.isCancelled && !stopped {
            var pinger: Task<Void, Never>?
            do {
                let connection = try await transport.openSocket(
                    url,
                    headers: ["X-Sonos-Api-Key": LocalAPIClient.apiKey],
                    protocols: [Self.subprotocol]
                )
                self.connection = connection
                for subscription in desired {
                    try await connection.send(subscription.frame(command: "subscribe"))
                }
                active = desired
                attempt = 0
                continuation.yield(.connected)
                pinger = Task {
                    while !Task.isCancelled {
                        try? await Task.sleep(for: Self.pingInterval)
                        if Task.isCancelled { break }
                        try? await connection.ping()
                    }
                }
                for try await data in connection.messages() {
                    if let event = try? SocketFrameDecoder.decode(data) {
                        continuation.yield(.event(event))
                    }
                }
            } catch {
                // fall through to reconnect
            }
            pinger?.cancel()
            connection = nil
            active = []
            if stopped || Task.isCancelled { return }
            continuation.yield(.disconnected)
            try? await Task.sleep(for: backoff.delay(attempt: attempt, random: Double.random(in: 0...1)))
            attempt += 1
        }
    }
}
```

- [ ] **Step 6: Run the tests to verify they pass**

```bash
swift test --filter PlayerSocketTests 2>&1 | tail -3
```
Expected: `4 tests passed`. If `stopEndsTheOutputStream` hangs, check that `stop()` calls `continuation.finish()` and that `run()` returns without yielding after `stopped` is set.

- [ ] **Step 7: Commit**

```bash
git add Packages/SonosKit
git commit -m "feat(sonoskit): add reconnecting player websocket with backoff"
```

---

### Task 8: SOAP helpers and UPnP EQ client

**Files:**
- Create: `Packages/SonosKit/Sources/SonosKit/UPnP/SOAP.swift`
- Create: `Packages/SonosKit/Sources/SonosKit/UPnP/UPnPClient.swift`
- Test: `Packages/SonosKit/Tests/SonosKitTests/SOAPTests.swift`
- Test: `Packages/SonosKit/Tests/SonosKitTests/UPnPClientTests.swift`

**Interfaces:**
- Consumes: `Transport`, `APIRequest`, `EQSettings`, `FakeTransport`.
- Produces:
  - `enum SOAP { static let serviceURN; static func envelope(action: String, arguments: [(name: String, value: String)]) -> String; static func escape(_:) -> String; static func value(named: String, in xml: String) -> String?; static func faultCode(in xml: String) -> Int? }`
  - `public enum UPnPError: Error, Hashable, Sendable { case fault(code: Int), http(status: Int), missingValue(String) }`
  - `public struct UPnPClient: Sendable { init(transport:); bass(address:) -> Int; setBass(_:address:); treble(address:) -> Int; setTreble(_:address:); loudness(address:) -> Bool; setLoudness(_:address:); eq(type:address:) -> Int?; setEQ(type:value:address:); hasSub(address:) -> Bool; eqSettings(address:hasSub:) -> EQSettings; apply(_ eq: EQSettings, address:) }` all `async throws`.

- [ ] **Step 1: Write the failing SOAP tests**

`Packages/SonosKit/Tests/SonosKitTests/SOAPTests.swift`:
```swift
import Testing
@testable import SonosKit

@Suite struct SOAPTests {
    @Test func envelopeWrapsActionAndArguments() {
        let xml = SOAP.envelope(action: "SetBass", arguments: [("InstanceID", "0"), ("DesiredBass", "-3")])
        #expect(xml.hasPrefix(#"<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body>"#))
        #expect(xml.contains(#"<u:SetBass xmlns:u="urn:schemas-upnp-org:service:RenderingControl:1"><InstanceID>0</InstanceID><DesiredBass>-3</DesiredBass></u:SetBass>"#))
        #expect(xml.hasSuffix("</s:Body></s:Envelope>"))
    }

    @Test func argumentsAreEscaped() {
        #expect(SOAP.escape("a<b&c>\"d'") == "a&lt;b&amp;c&gt;&quot;d&apos;")
    }

    @Test func extractsValuesFromFixtures() {
        #expect(SOAP.value(named: "CurrentBass", in: Fixtures.string("soap_GetBass.xml")) == "-3")
        #expect(SOAP.value(named: "CurrentValue", in: Fixtures.string("soap_GetEQ_SubGain.xml")) == "-2")
        #expect(SOAP.value(named: "CurrentLoudness", in: Fixtures.string("soap_GetLoudness.xml")) == "1")
        #expect(SOAP.value(named: "CurrentBass", in: Fixtures.string("soap_SetBass.xml")) == nil)
    }

    @Test func extractsFaultCode() {
        #expect(SOAP.faultCode(in: Fixtures.string("soap_fault.xml")) == 402)
        #expect(SOAP.faultCode(in: Fixtures.string("soap_GetBass.xml")) == nil)
    }
}
```

- [ ] **Step 2: Run, verify failure, implement SOAP**

```bash
swift test --filter SOAPTests 2>&1 | tail -3
```
Expected: `cannot find 'SOAP'`.

`Packages/SonosKit/Sources/SonosKit/UPnP/SOAP.swift`:
```swift
import Foundation

/// Just enough SOAP for Sonos RenderingControl. No general XML parser: the responses are tiny and flat.
enum SOAP {
    static let serviceURN = "urn:schemas-upnp-org:service:RenderingControl:1"
    static let controlPath = "/MediaRenderer/RenderingControl/Control"

    static func envelope(action: String, arguments: [(name: String, value: String)]) -> String {
        let args = arguments.map { "<\($0.name)>\(escape($0.value))</\($0.name)>" }.joined()
        return #"<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body><u:\#(action) xmlns:u="\#(serviceURN)">\#(args)</u:\#(action)></s:Body></s:Envelope>"#
    }

    static func escape(_ value: String) -> String {
        var out = ""
        for character in value {
            switch character {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&apos;"
            default: out.append(character)
            }
        }
        return out
    }

    /// Text between `<name>` and `</name>`, or nil.
    static func value(named name: String, in xml: String) -> String? {
        guard let open = xml.range(of: "<\(name)>"),
              let close = xml.range(of: "</\(name)>", range: open.upperBound..<xml.endIndex) else { return nil }
        return String(xml[open.upperBound..<close.lowerBound])
    }

    static func faultCode(in xml: String) -> Int? {
        guard xml.contains("<s:Fault>") else { return nil }
        return value(named: "errorCode", in: xml).flatMap { Int($0) }
    }
}
```

```bash
swift test --filter SOAPTests 2>&1 | tail -3
```
Expected: `4 tests passed`.

- [ ] **Step 3: Write the failing UPnPClient tests**

`Packages/SonosKit/Tests/SonosKitTests/UPnPClientTests.swift`:
```swift
import Foundation
import Testing
@testable import SonosKit

@Suite struct UPnPClientTests {
    let transport = FakeTransport()
    var client: UPnPClient { UPnPClient(transport: transport) }

    @Test func getBassPostsSoapToPort1400AndParsesValue() async throws {
        transport.respond(whenPathContains: "RenderingControl", body: Fixtures.data("soap_GetBass.xml"))
        let bass = try await client.bass(address: "192.168.1.105")
        #expect(bass == -3)
        let request = try #require(transport.requests.first)
        #expect(request.method == "POST")
        #expect(request.url.absoluteString == "http://192.168.1.105:1400/MediaRenderer/RenderingControl/Control")
        #expect(request.headers["SOAPACTION"] == "\"urn:schemas-upnp-org:service:RenderingControl:1#GetBass\"")
        #expect(request.headers["Content-Type"] == "text/xml; charset=\"utf-8\"")
        let body = String(decoding: try #require(request.body), as: UTF8.self)
        #expect(body.contains("<u:GetBass "))
        #expect(body.contains("<InstanceID>0</InstanceID>"))
    }

    @Test func settersSendDesiredValues() async throws {
        transport.respond(whenPathContains: "RenderingControl", body: Fixtures.data("soap_SetBass.xml"))
        try await client.setBass(4, address: "192.168.1.105")
        try await client.setTreble(-2, address: "192.168.1.105")
        try await client.setLoudness(false, address: "192.168.1.105")
        try await client.setEQ(type: "SubGain", value: 3, address: "192.168.1.105")
        let bodies = transport.requests.map { String(decoding: $0.body ?? Data(), as: UTF8.self) }
        #expect(bodies[0].contains("<DesiredBass>4</DesiredBass>"))
        #expect(bodies[1].contains("<DesiredTreble>-2</DesiredTreble>"))
        #expect(bodies[2].contains("<Channel>Master</Channel><DesiredLoudness>0</DesiredLoudness>"))
        #expect(bodies[3].contains("<EQType>SubGain</EQType><DesiredValue>3</DesiredValue>"))
    }

    @Test func faultBecomesTypedErrorAndEqTreats402AsUnavailable() async throws {
        transport.respond(whenPathContains: "RenderingControl", status: 500, body: Fixtures.data("soap_fault.xml"))
        await #expect(throws: UPnPError.fault(code: 402)) {
            _ = try await client.bass(address: "192.168.1.105")
        }
        let value = try await client.eq(type: "NightMode", address: "192.168.1.105")
        #expect(value == nil)
    }

    @Test func hasSubUsesCrossover() async throws {
        transport.respond(whenPathContains: "RenderingControl", body: Data(SOAP.envelope(action: "GetEQResponse", arguments: [("CurrentValue", "99")]).utf8))
        #expect(try await client.hasSub(address: "192.168.1.105"))
        transport.respond(whenPathContains: "RenderingControl", body: Data(SOAP.envelope(action: "GetEQResponse", arguments: [("CurrentValue", "0")]).utf8))
        #expect(!(try await client.hasSub(address: "192.168.1.28")))
        let body = String(decoding: transport.requests[0].body ?? Data(), as: UTF8.self)
        #expect(body.contains("<EQType>SubCrossover</EQType>"))
    }

    @Test func eqSettingsReadsEverythingAndSkipsSubWithoutOne() async throws {
        transport.respond(whenPathContains: "RenderingControl", sequence: [
            StubResponse(body: Fixtures.data("soap_GetBass.xml")),
            StubResponse(body: Data(SOAP.envelope(action: "GetTrebleResponse", arguments: [("CurrentTreble", "2")]).utf8)),
            StubResponse(body: Fixtures.data("soap_GetLoudness.xml")),
            StubResponse(body: Fixtures.data("soap_GetEQ_SubGain.xml")),
        ])
        let withSub = try await client.eqSettings(address: "192.168.1.105", hasSub: true)
        #expect(withSub == EQSettings(bass: -3, treble: 2, loudness: true, subGain: -2))
        #expect(transport.requests.count == 4)

        let other = FakeTransport()
        other.respond(whenPathContains: "RenderingControl", sequence: [
            StubResponse(body: Fixtures.data("soap_GetBass.xml")),
            StubResponse(body: Data(SOAP.envelope(action: "GetTrebleResponse", arguments: [("CurrentTreble", "0")]).utf8)),
            StubResponse(body: Fixtures.data("soap_GetLoudness.xml")),
        ])
        let noSub = try await UPnPClient(transport: other).eqSettings(address: "192.168.1.28", hasSub: false)
        #expect(noSub.subGain == nil)
        #expect(other.requests.count == 3)
    }

    @Test func applyWritesOnlyWhatExists() async throws {
        transport.respond(whenPathContains: "RenderingControl", body: Fixtures.data("soap_SetBass.xml"))
        try await client.apply(EQSettings(bass: 1, treble: 2, loudness: true, subGain: nil), address: "192.168.1.28")
        #expect(transport.requests.count == 3)
        try await client.apply(EQSettings(bass: 1, treble: 2, loudness: true, subGain: -5), address: "192.168.1.105")
        #expect(transport.requests.count == 7)
    }
}
```

- [ ] **Step 4: Run, verify failure, implement UPnPClient**

```bash
swift test --filter UPnPClientTests 2>&1 | tail -3
```
Expected: `cannot find 'UPnPClient'`.

`Packages/SonosKit/Sources/SonosKit/UPnP/UPnPClient.swift`:
```swift
import Foundation

public enum UPnPError: Error, Hashable, Sendable {
    case fault(code: Int)
    case http(status: Int)
    case missingValue(String)
}

/// EQ over UPnP RenderingControl on port 1400. Everything here is per player, not per group.
public struct UPnPClient: Sendable {
    public static let port = 1400

    private let transport: any Transport

    public init(transport: any Transport) {
        self.transport = transport
    }

    public func bass(address: String) async throws -> Int {
        try await intValue("CurrentBass", action: "GetBass", arguments: [("InstanceID", "0")], address: address)
    }

    public func setBass(_ value: Int, address: String) async throws {
        _ = try await call(action: "SetBass", arguments: [("InstanceID", "0"), ("DesiredBass", String(value))], address: address)
    }

    public func treble(address: String) async throws -> Int {
        try await intValue("CurrentTreble", action: "GetTreble", arguments: [("InstanceID", "0")], address: address)
    }

    public func setTreble(_ value: Int, address: String) async throws {
        _ = try await call(action: "SetTreble", arguments: [("InstanceID", "0"), ("DesiredTreble", String(value))], address: address)
    }

    public func loudness(address: String) async throws -> Bool {
        try await intValue("CurrentLoudness", action: "GetLoudness", arguments: [("InstanceID", "0"), ("Channel", "Master")], address: address) == 1
    }

    public func setLoudness(_ on: Bool, address: String) async throws {
        _ = try await call(action: "SetLoudness", arguments: [("InstanceID", "0"), ("Channel", "Master"), ("DesiredLoudness", on ? "1" : "0")], address: address)
    }

    /// nil when the player answers fault 402 (EQ type not supported on this model).
    public func eq(type: String, address: String) async throws -> Int? {
        do {
            return try await intValue("CurrentValue", action: "GetEQ", arguments: [("InstanceID", "0"), ("EQType", type)], address: address)
        } catch UPnPError.fault(code: 402) {
            return nil
        }
    }

    public func setEQ(type: String, value: Int, address: String) async throws {
        _ = try await call(action: "SetEQ", arguments: [("InstanceID", "0"), ("EQType", type), ("DesiredValue", String(value))], address: address)
    }

    /// A sub is attached when the crossover frequency is non-zero (Amp with a wired sub reports 99).
    public func hasSub(address: String) async throws -> Bool {
        (try await eq(type: "SubCrossover", address: address) ?? 0) > 0
    }

    public func eqSettings(address: String, hasSub: Bool) async throws -> EQSettings {
        let bass = try await bass(address: address)
        let treble = try await treble(address: address)
        let loudness = try await loudness(address: address)
        let subGain = hasSub ? try await eq(type: "SubGain", address: address) : nil
        return EQSettings(bass: bass, treble: treble, loudness: loudness, subGain: subGain)
    }

    public func apply(_ eq: EQSettings, address: String) async throws {
        try await setBass(eq.bass, address: address)
        try await setTreble(eq.treble, address: address)
        try await setLoudness(eq.loudness, address: address)
        if let subGain = eq.subGain {
            try await setEQ(type: "SubGain", value: subGain, address: address)
        }
    }

    // MARK: Plumbing

    private func intValue(_ name: String, action: String, arguments: [(name: String, value: String)], address: String) async throws -> Int {
        let xml = try await call(action: action, arguments: arguments, address: address)
        guard let text = SOAP.value(named: name, in: xml), let value = Int(text) else {
            throw UPnPError.missingValue(name)
        }
        return value
    }

    private func call(action: String, arguments: [(name: String, value: String)], address: String) async throws -> String {
        guard let url = URL(string: "http://\(address):\(Self.port)\(SOAP.controlPath)") else {
            preconditionFailure("Bad UPnP URL for \(address)")
        }
        let request = APIRequest(
            method: "POST",
            url: url,
            headers: [
                "Content-Type": "text/xml; charset=\"utf-8\"",
                "SOAPACTION": "\"\(SOAP.serviceURN)#\(action)\"",
            ],
            body: Data(SOAP.envelope(action: action, arguments: arguments).utf8)
        )
        let response = try await transport.send(request)
        let xml = String(decoding: response.body, as: UTF8.self)
        guard (200..<300).contains(response.status) else {
            if let code = SOAP.faultCode(in: xml) { throw UPnPError.fault(code: code) }
            throw UPnPError.http(status: response.status)
        }
        return xml
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
swift test --filter UPnPClientTests 2>&1 | tail -3
```
Expected: `6 tests passed`.

- [ ] **Step 6: Commit**

```bash
git add Packages/SonosKit
git commit -m "feat(sonoskit): add UPnP EQ client with SOAP helpers"
```

---
### Task 9: Discovery protocol and Bonjour implementation

**Files:**
- Create: `Packages/SonosKit/Sources/SonosKit/Discovery/Discovering.swift`
- Create: `Packages/SonosKit/Sources/SonosKit/Discovery/BonjourDiscovery.swift`
- Create: `Packages/SonosKit/Tests/SonosKitTests/Support/FakeDiscovery.swift`
- Test: `Packages/SonosKit/Tests/SonosKitTests/DiscoveryTests.swift`

**Interfaces:**
- Produces:
  - `public struct DiscoveredPlayer: Hashable, Sendable { id: String; address: String; householdID: String? }`
  - `public enum DiscoveryEvent: Hashable, Sendable { case found(DiscoveredPlayer), lost(playerID: String), permissionDenied }`
  - `public protocol Discovering: Sendable { func events() -> AsyncStream<DiscoveryEvent>; func stop() }`
  - `public final class BonjourDiscovery: Discovering` with `static func player(fromTXT txt: [String: String]) -> DiscoveredPlayer?`
  - Test double `FakeDiscovery` with `emit(_ event: DiscoveryEvent)`.

The TXT record a player advertises (verified): `uuid=RINCON_347E5C04E98101400`, `hhid=Sonos_…`, `location=http://192.168.1.105:1400/xml/device_description.xml`, `sslport=1443`, `wss=/websocket/api`, `variant=2`. The address comes from the `location` URL's host.

- [ ] **Step 1: Write the failing tests**

`Packages/SonosKit/Tests/SonosKitTests/DiscoveryTests.swift`:
```swift
import Testing
@testable import SonosKit

@Suite struct DiscoveryTests {
    @Test func parsesPlayerFromTXTRecord() {
        let txt = [
            "uuid": "RINCON_347E5C04E98101400",
            "hhid": "Sonos_DzRiRrFKF13cB3mZaqqRgpvjhm",
            "location": "http://192.168.1.105:1400/xml/device_description.xml",
            "sslport": "1443",
            "variant": "2",
        ]
        let player = BonjourDiscovery.player(fromTXT: txt)
        #expect(player == DiscoveredPlayer(id: "RINCON_347E5C04E98101400", address: "192.168.1.105", householdID: "Sonos_DzRiRrFKF13cB3mZaqqRgpvjhm"))
    }

    @Test func recordWithoutUUIDOrLocationIsIgnored() {
        #expect(BonjourDiscovery.player(fromTXT: ["location": "http://192.168.1.105:1400/x"]) == nil)
        #expect(BonjourDiscovery.player(fromTXT: ["uuid": "RINCON_1"]) == nil)
        #expect(BonjourDiscovery.player(fromTXT: ["uuid": "RINCON_1", "location": "not a url"]) == nil)
    }

    @Test func fakeDiscoveryDeliversEvents() async {
        let discovery = FakeDiscovery()
        var iterator = discovery.events().makeAsyncIterator()
        discovery.emit(.found(DiscoveredPlayer(id: "RINCON_1", address: "192.168.1.5", householdID: nil)))
        discovery.emit(.lost(playerID: "RINCON_1"))
        #expect(await iterator.next() == .found(DiscoveredPlayer(id: "RINCON_1", address: "192.168.1.5", householdID: nil)))
        #expect(await iterator.next() == .lost(playerID: "RINCON_1"))
    }
}
```

- [ ] **Step 2: Run to verify failure**

```bash
swift test --filter DiscoveryTests 2>&1 | tail -3
```
Expected: `cannot find 'BonjourDiscovery'`.

- [ ] **Step 3: Write the protocol, the Bonjour browser, and the fake**

`Packages/SonosKit/Sources/SonosKit/Discovery/Discovering.swift`:
```swift
import Foundation

public struct DiscoveredPlayer: Hashable, Sendable {
    public var id: String
    public var address: String
    public var householdID: String?

    public init(id: String, address: String, householdID: String?) {
        self.id = id
        self.address = address
        self.householdID = householdID
    }
}

public enum DiscoveryEvent: Hashable, Sendable {
    case found(DiscoveredPlayer)
    case lost(playerID: String)
    /// macOS Local Network permission was denied for this app.
    case permissionDenied
}

public protocol Discovering: Sendable {
    /// Starts browsing on first call. Ends when `stop()` is called.
    func events() -> AsyncStream<DiscoveryEvent>
    func stop()
}
```

`Packages/SonosKit/Sources/SonosKit/Discovery/BonjourDiscovery.swift`:
```swift
import Foundation
import Network
import Synchronization

/// Browses `_sonos._tcp` with NWBrowser. Works inside the App Sandbox as long as Info.plist
/// lists the service in NSBonjourServices and has NSLocalNetworkUsageDescription.
public final class BonjourDiscovery: Discovering, @unchecked Sendable {
    public static let serviceType = "_sonos._tcp"
    private static let policyDenied: Int32 = -65570 // kDNSServiceErr_PolicyDenied

    private let browser = Mutex<NWBrowser?>(nil)

    public init() {}

    public static func player(fromTXT txt: [String: String]) -> DiscoveredPlayer? {
        guard let id = txt["uuid"], !id.isEmpty,
              let location = txt["location"],
              let host = URLComponents(string: location)?.host, !host.isEmpty else { return nil }
        return DiscoveredPlayer(id: id, address: host, householdID: txt["hhid"])
    }

    public func events() -> AsyncStream<DiscoveryEvent> {
        let (stream, continuation) = AsyncStream<DiscoveryEvent>.makeStream()
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: Self.serviceType, domain: nil), using: NWParameters())

        browser.stateUpdateHandler = { state in
            if case .waiting(let error) = state, case .dns(let code) = error, code == Self.policyDenied {
                continuation.yield(.permissionDenied)
            }
            if case .failed(let error) = state, case .dns(let code) = error, code == Self.policyDenied {
                continuation.yield(.permissionDenied)
            }
        }

        browser.browseResultsChangedHandler = { _, changes in
            for change in changes {
                switch change {
                case .added(let result):
                    if let player = Self.player(from: result) { continuation.yield(.found(player)) }
                case .changed(_, let result, let flags) where flags.contains(.metadataChanged):
                    if let player = Self.player(from: result) { continuation.yield(.found(player)) }
                case .removed(let result):
                    if let player = Self.player(from: result) { continuation.yield(.lost(playerID: player.id)) }
                default:
                    break
                }
            }
        }

        continuation.onTermination = { _ in browser.cancel() }
        self.browser.withLock { old in
            old?.cancel()
            old = browser
        }
        browser.start(queue: DispatchQueue(label: "sonoskit.bonjour"))
        return stream
    }

    public func stop() {
        browser.withLock { $0?.cancel(); $0 = nil }
    }

    private static func player(from result: NWBrowser.Result) -> DiscoveredPlayer? {
        guard case .bonjour(let record) = result.metadata else { return nil }
        return player(fromTXT: record.dictionary)
    }
}
```

`Packages/SonosKit/Tests/SonosKitTests/Support/FakeDiscovery.swift`:
```swift
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
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
swift test --filter DiscoveryTests 2>&1 | tail -3
```
Expected: `3 tests passed`. If `NWBrowser.Result.Change.changed` has a different pattern shape in this SDK, match `.changed(old:new:flags:)` labels as the compiler suggests.

- [ ] **Step 5: Commit**

```bash
git add Packages/SonosKit
git commit -m "feat(sonoskit): add Bonjour discovery"
```

---

### Task 10: SubscriptionPlan

**Files:**
- Create: `Packages/SonosKit/Sources/SonosKit/Household/SubscriptionPlan.swift`
- Test: `Packages/SonosKit/Tests/SonosKitTests/SubscriptionPlanTests.swift`

**Interfaces:**
- Consumes: `Group`, `Player`, `Subscription`.
- Produces: `enum SubscriptionPlan { static func make(groups: [Group], players: [Player], gatewayID: String?) -> [String: Set<Subscription>] }` keyed by player id.

Rules: every player gets `playerVolume:1` scoped to itself. Every group coordinator additionally gets `playback:1`, `playbackMetadata:1`, `groupVolume:1` scoped to its group. The gateway player (or, if the gateway is nil or missing, the first player by id) additionally gets household-scoped `groups:1` and `favorites:1`.

- [ ] **Step 1: Write the failing test**

`Packages/SonosKit/Tests/SonosKitTests/SubscriptionPlanTests.swift`:
```swift
import Foundation
import Testing
@testable import SonosKit

@Suite struct SubscriptionPlanTests {
    func snapshot() throws -> HouseholdSnapshot {
        let response = try JSONDecoder().decode(GroupsResponse.self, from: Fixtures.data("groups.json"))
        return SnapshotReducer.reduce(HouseholdSnapshot(), .topology(groups: response.groups, players: response.players))
    }

    @Test func coordinatorsGetGroupNamespacesMembersOnlyPlayerVolume() throws {
        let s = try snapshot()
        let plan = SubscriptionPlan.make(groups: s.groups, players: s.players, gatewayID: "RINCON_347E5C04E98101400")
        let gid = "RINCON_542A1B73A25001400:620674909"

        let flyttbar = try #require(plan["RINCON_542A1B73A25001400"])
        #expect(flyttbar == [
            Subscription(namespace: "playerVolume:1", scope: .player("RINCON_542A1B73A25001400")),
            Subscription(namespace: "playback:1", scope: .group(gid)),
            Subscription(namespace: "playbackMetadata:1", scope: .group(gid)),
            Subscription(namespace: "groupVolume:1", scope: .group(gid)),
        ])

        let stereo = try #require(plan["RINCON_347E5C04E98101400"])
        #expect(stereo == [
            Subscription(namespace: "playerVolume:1", scope: .player("RINCON_347E5C04E98101400")),
            Subscription(namespace: "groups:1", scope: .household),
            Subscription(namespace: "favorites:1", scope: .household),
        ])
        #expect(plan.count == 4)
    }

    @Test func missingGatewayFallsBackToFirstPlayerByID() throws {
        let s = try snapshot()
        let plan = SubscriptionPlan.make(groups: s.groups, players: s.players, gatewayID: nil)
        let household = plan.filter { $0.value.contains(Subscription(namespace: "groups:1", scope: .household)) }
        #expect(household.keys.first == "RINCON_347E5C04E98101400")
        #expect(household.count == 1)
    }
}
```

- [ ] **Step 2: Run to verify failure, then implement**

```bash
swift test --filter SubscriptionPlanTests 2>&1 | tail -3
```

`Packages/SonosKit/Sources/SonosKit/Household/SubscriptionPlan.swift`:
```swift
import Foundation

/// Which websocket subscribes to what. Pure so it can be tested and diffed.
enum SubscriptionPlan {
    static let householdNamespaces = ["groups:1", "favorites:1"]
    static let groupNamespaces = ["playback:1", "playbackMetadata:1", "groupVolume:1"]

    static func make(groups: [Group], players: [Player], gatewayID: String?) -> [String: Set<Subscription>] {
        var plan: [String: Set<Subscription>] = [:]
        for player in players {
            plan[player.id] = [Subscription(namespace: "playerVolume:1", scope: .player(player.id))]
        }
        for group in groups {
            for namespace in groupNamespaces {
                plan[group.coordinatorID, default: []].insert(Subscription(namespace: namespace, scope: .group(group.id)))
            }
        }
        let gateway = players.first { $0.id == gatewayID }?.id ?? players.map(\.id).sorted().first
        if let gateway {
            for namespace in householdNamespaces {
                plan[gateway, default: []].insert(Subscription(namespace: namespace, scope: .household))
            }
        }
        return plan
    }
}
```

```bash
swift test --filter SubscriptionPlanTests 2>&1 | tail -3
```
Expected: `2 tests passed`.

- [ ] **Step 3: Commit**

```bash
git add Packages/SonosKit
git commit -m "feat(sonoskit): add subscription plan"
```

---

### Task 11: Household actor

**Files:**
- Create: `Packages/SonosKit/Sources/SonosKit/Household/Household.swift`
- Test: `Packages/SonosKit/Tests/SonosKitTests/HouseholdTests.swift`

**Interfaces:**
- Consumes: everything from Tasks 2–10.
- Produces the public `Household` actor exactly as listed in the interfaces block at the top, plus `public struct Household.Configuration: Sendable { discoveryTimeout: Duration = .seconds(10); backoff: Backoff = Backoff() }` and `public enum HouseholdError: Error, Hashable, Sendable { case unknownGroup, unknownPlayer, notReady }`.

Behaviour:
1. `start()`: status `.discovering`; consume discovery; start a timeout task that sets `.noPlayersFound` if no player has been found when it fires.
2. First `found` player becomes the gateway. Its address is allowed in the trust store. Fetch groups over REST from it, apply `.topology`, allow every player address, set `.ready`, fetch favorites, open a `PlayerSocket` per player, apply the subscription plan, then probe `hasSub` for every player once.
3. Later `found` events only update the trust store and the known-address table. `lost` applies `.playerRemoved` and stops that socket. `permissionDenied` sets `.localNetworkDenied`.
4. Socket `.event`s are mapped to `HouseholdEvent`s. A `.groups` event re-applies topology, opens sockets for new players, stops sockets for gone players, and re-applies the subscription plan. `.favoritesChanged` re-fetches favorites.
5. Group commands resolve the coordinator address from the snapshot and call `LocalAPIClient`. On `coordinatorMoved` or `groupGone` the household re-fetches topology and retries once with the new coordinator.
6. `invalidAPIKey` or `unauthorized` from the topology fetch sets `.unauthorized`.
7. Snapshots are published to every stream returned by `snapshots()`; a new subscriber immediately receives the current snapshot.

- [ ] **Step 1: Write the failing tests**

`Packages/SonosKit/Tests/SonosKitTests/HouseholdTests.swift`:
```swift
import Foundation
import Testing
@testable import SonosKit

@Suite struct HouseholdTests {
    let gid = "RINCON_542A1B73A25001400:620674909"
    let stereo = DiscoveredPlayer(id: "RINCON_347E5C04E98101400", address: "192.168.1.105", householdID: "HH")

    struct Harness {
        let discovery = FakeDiscovery()
        let transport = FakeTransport()
        let trust = TrustStore()
        let household: Household

        init(timeout: Duration = .seconds(5)) {
            transport.respond(whenPathContains: "/households/local/groups", body: Fixtures.data("groups.json"))
            transport.respond(whenPathContains: "/households/local/favorites", body: Fixtures.data("favorites.json"))
            transport.respond(whenPathContains: "RenderingControl", body: Data(SOAP.envelope(action: "GetEQResponse", arguments: [("CurrentValue", "0")]).utf8))
            var configuration = Household.Configuration()
            configuration.discoveryTimeout = timeout
            configuration.backoff = Backoff(base: .milliseconds(1), max: .milliseconds(5), jitter: 0)
            household = Household(discovery: discovery, transport: transport, trustStore: trust, configuration: configuration)
        }

        func startAndDiscover(_ player: DiscoveredPlayer) async throws -> HouseholdSnapshot {
            let stream = await household.snapshots()
            await household.start()
            discovery.emit(.found(player))
            for await snapshot in stream where snapshot.status == .ready && snapshot.favorites.count == 1 {
                return snapshot
            }
            throw WaitTimeout()
        }
    }

    @Test func discoveryLeadsToReadySnapshotSocketsAndSubscriptions() async throws {
        let h = Harness()
        let ready = try await h.startAndDiscover(stereo)
        #expect(ready.groups.map(\.name) == ["Elsas Sovrum", "Flyttbar + 1", "Sovrum"])
        #expect(ready.favorites.map(\.name) == ["P3"])
        #expect(h.trust.shouldTrust(host: "192.168.1.216"))
        try await waitUntil { h.transport.socketCount == 4 }
        let flyttbar = try #require(h.transport.socket(forHost: "192.168.1.216"))
        try await waitUntil { flyttbar.sentText.count == 4 }
        #expect(flyttbar.sentText.contains { $0.contains(#""namespace":"playbackMetadata:1""#) && $0.contains(gid) })
        let stereoSocket = try #require(h.transport.socket(forHost: "192.168.1.105"))
        try await waitUntil { stereoSocket.sentText.count == 3 }
        #expect(stereoSocket.sentText.contains { $0.contains(#""namespace":"groups:1""#) })
        // One SubCrossover probe per player.
        try await waitUntil { h.transport.requests(matching: "RenderingControl").count == 4 }
        await h.household.stop()
    }

    @Test func socketEventsUpdateTheSnapshot() async throws {
        let h = Harness()
        _ = try await h.startAndDiscover(stereo)
        try await waitUntil { h.transport.socket(forHost: "192.168.1.216") != nil }
        let socket = try #require(h.transport.socket(forHost: "192.168.1.216"))
        socket.push(#"[{"namespace":"groupVolume:1","type":"groupVolume","groupId":"\#(gid)"},{"volume":33,"muted":true,"fixed":false}]"#)
        try await waitUntil { await h.household.current.group(gid)?.volume == Volume(level: 33, muted: true, fixed: false) }
        socket.push(#"[{"namespace":"playerVolume:1","type":"playerVolume","playerId":"RINCON_542A1B73A25001400"},{"volume":9,"muted":false,"fixed":false}]"#)
        try await waitUntil { await h.household.current.playerVolumes["RINCON_542A1B73A25001400"]?.level == 9 }
        await h.household.stop()
    }

    @Test func groupCommandsGoToTheCoordinator() async throws {
        let h = Harness()
        _ = try await h.startAndDiscover(stereo)
        try await h.household.play(group: gid)
        try await h.household.setGroupVolume(21, group: gid)
        try await h.household.setPlayerVolume(7, player: "RINCON_48A6B8194D2A01400")
        try await h.household.playFavorite("3", group: gid)
        try await h.household.setGroupMembers(["RINCON_542A1B73A25001400"], group: gid)
        let posts = h.transport.requests.filter { $0.method == "POST" && $0.url.port == 1443 }.map { $0.url.absoluteString }
        #expect(posts == [
            "https://192.168.1.216:1443/api/v1/groups/\(gid)/playback/play",
            "https://192.168.1.216:1443/api/v1/groups/\(gid)/groupVolume",
            "https://192.168.1.28:1443/api/v1/players/RINCON_48A6B8194D2A01400/playerVolume",
            "https://192.168.1.216:1443/api/v1/groups/\(gid)/favorites",
            "https://192.168.1.216:1443/api/v1/groups/\(gid)/groups/setGroupMembers",
        ])
        await #expect(throws: HouseholdError.unknownGroup) { try await h.household.pause(group: "nope") }
        await h.household.stop()
    }

    @Test func coordinatorMovedRefetchesTopologyAndRetries() async throws {
        let h = Harness()
        _ = try await h.startAndDiscover(stereo)
        h.transport.respond(whenPathContains: "/playback/pause", sequence: [
            StubResponse(status: 404, body: Fixtures.data("error_404_coordinator_moved.json")),
            StubResponse(),
        ])
        let groupsBefore = h.transport.requests(matching: "/households/local/groups").count
        try await h.household.pause(group: gid)
        #expect(h.transport.requests(matching: "/playback/pause").count == 2)
        #expect(h.transport.requests(matching: "/households/local/groups").count == groupsBefore + 1)
        await h.household.stop()
    }

    @Test func eqReadsAndWritesThroughUPnP() async throws {
        let h = Harness()
        _ = try await h.startAndDiscover(stereo)
        h.transport.respond(whenPathContains: "RenderingControl", sequence: [
            StubResponse(body: Fixtures.data("soap_GetBass.xml")),
            StubResponse(body: Data(SOAP.envelope(action: "GetTrebleResponse", arguments: [("CurrentTreble", "1")]).utf8)),
            StubResponse(body: Fixtures.data("soap_GetLoudness.xml")),
        ])
        let eq = try await h.household.eq(player: "RINCON_48A6B8194D2A01400")
        #expect(eq == EQSettings(bass: -3, treble: 1, loudness: true, subGain: nil))
        try await h.household.setEQ(EQSettings(bass: 0, treble: 0, loudness: false, subGain: nil), player: "RINCON_48A6B8194D2A01400")
        #expect(h.transport.requests.filter { $0.url.host() == "192.168.1.28" && $0.url.port == 1400 }.count >= 6)
        await #expect(throws: HouseholdError.unknownPlayer) { _ = try await h.household.eq(player: "nope") }
        await h.household.stop()
    }

    @Test func topologyEventOpensAndClosesSockets() async throws {
        let h = Harness()
        _ = try await h.startAndDiscover(stereo)
        try await waitUntil { h.transport.socketCount == 4 }
        let stereoSocket = try #require(h.transport.socket(forHost: "192.168.1.105"))
        let lines = Fixtures.lines("events.jsonl")
        let groupsEvent = try #require(lines.first { $0.contains(#""type":"groups""#) })
        // Same 4 players, so no new sockets; Flyttbar keeps its coordinator role.
        stereoSocket.push(groupsEvent)
        try await waitUntil { await h.household.current.groups.map(\.name) == ["Elsas Sovrum", "Flyttbar + 1", "Sovrum"] }
        #expect(h.transport.socketCount == 4)

        h.discovery.emit(.lost(playerID: "RINCON_48A6B8194D2A01400"))
        try await waitUntil { await h.household.current.player("RINCON_48A6B8194D2A01400") == nil }
        #expect(await h.household.current.groups.map(\.name) == ["Elsas Sovrum", "Flyttbar + 1"])
        await h.household.stop()
    }

    @Test func noPlayersWithinTimeoutSetsStatus() async throws {
        let h = Harness(timeout: .milliseconds(30))
        let stream = await h.household.snapshots()
        await h.household.start()
        for await snapshot in stream where snapshot.status == .noPlayersFound { break }
        #expect(await h.household.current.status == .noPlayersFound)
        await h.household.stop()
    }

    @Test func invalidKeySetsUnauthorized() async throws {
        let h = Harness()
        h.transport.respond(whenPathContains: "/households/local/groups", status: 400, body: Fixtures.data("error_400_nokey.json"))
        let stream = await h.household.snapshots()
        await h.household.start()
        h.discovery.emit(.found(stereo))
        for await snapshot in stream where snapshot.status == .unauthorized { break }
        #expect(await h.household.current.status == .unauthorized)
        await h.household.stop()
    }

    @Test func permissionDeniedSetsStatus() async throws {
        let h = Harness()
        let stream = await h.household.snapshots()
        await h.household.start()
        h.discovery.emit(.permissionDenied)
        for await snapshot in stream where snapshot.status == .localNetworkDenied { break }
        #expect(await h.household.current.status == .localNetworkDenied)
        await h.household.stop()
    }
}
```

- [ ] **Step 2: Run to verify failure**

```bash
swift test --filter HouseholdTests 2>&1 | tail -3
```
Expected: `cannot find 'Household'`.

- [ ] **Step 3: Write the actor**

`Packages/SonosKit/Sources/SonosKit/Household/Household.swift`:
```swift
import Foundation

public enum HouseholdError: Error, Hashable, Sendable {
    case unknownGroup
    case unknownPlayer
    case notReady
}

/// Owns discovery, one socket per player, the REST and UPnP clients, and the snapshot.
/// Everything the app needs goes through here.
public actor Household {
    public struct Configuration: Sendable {
        public var discoveryTimeout: Duration = .seconds(10)
        public var backoff = Backoff()
        public init() {}
    }

    private let discovery: any Discovering
    private let transport: any Transport
    private let trustStore: TrustStore?
    private let configuration: Configuration
    private let api: LocalAPIClient
    private let upnp: UPnPClient

    private var snapshot = HouseholdSnapshot()
    private var observers: [UUID: AsyncStream<HouseholdSnapshot>.Continuation] = [:]
    private var sockets: [String: PlayerSocket] = [:]
    private var socketTasks: [String: Task<Void, Never>] = [:]
    private var gatewayID: String?
    private var addresses: [String: String] = [:]
    private var subProbed: Set<String> = []
    private var discoveryTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var started = false

    public init(discovery: any Discovering, transport: any Transport, trustStore: TrustStore? = nil, configuration: Configuration = .init()) {
        self.discovery = discovery
        self.transport = transport
        self.trustStore = trustStore
        self.configuration = configuration
        self.api = LocalAPIClient(transport: transport)
        self.upnp = UPnPClient(transport: transport)
    }

    // MARK: Lifecycle

    public var current: HouseholdSnapshot { snapshot }

    public func snapshots() -> AsyncStream<HouseholdSnapshot> {
        let (stream, continuation) = AsyncStream<HouseholdSnapshot>.makeStream()
        let id = UUID()
        observers[id] = continuation
        continuation.yield(snapshot)
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeObserver(id) }
        }
        return stream
    }

    public func start() {
        guard !started else { return }
        started = true
        apply(.status(.discovering))
        discoveryTask = Task { [weak self] in
            guard let self else { return }
            for await event in discovery.events() {
                await self.handle(discovery: event)
            }
        }
        timeoutTask = Task { [weak self, configuration] in
            try? await Task.sleep(for: configuration.discoveryTimeout)
            await self?.discoveryTimedOut()
        }
    }

    public func stop() {
        discoveryTask?.cancel()
        timeoutTask?.cancel()
        discovery.stop()
        for (id, socket) in sockets {
            socketTasks[id]?.cancel()
            Task { await socket.stop() }
        }
        sockets = [:]
        socketTasks = [:]
        for continuation in observers.values { continuation.finish() }
        observers = [:]
    }

    // MARK: Commands

    public func play(group id: String) async throws { try await groupCommand(id) { try await api.play(groupID: id, at: $0) } }
    public func pause(group id: String) async throws { try await groupCommand(id) { try await api.pause(groupID: id, at: $0) } }
    public func next(group id: String) async throws { try await groupCommand(id) { try await api.next(groupID: id, at: $0) } }
    public func previous(group id: String) async throws { try await groupCommand(id) { try await api.previous(groupID: id, at: $0) } }

    public func setGroupVolume(_ level: Int, group id: String) async throws {
        try await groupCommand(id) { try await api.setGroupVolume(level, groupID: id, at: $0) }
    }

    public func setGroupMuted(_ muted: Bool, group id: String) async throws {
        try await groupCommand(id) { try await api.setGroupMuted(muted, groupID: id, at: $0) }
    }

    public func playFavorite(_ favoriteID: String, group id: String) async throws {
        try await groupCommand(id) { try await api.loadFavorite(favoriteID, groupID: id, at: $0) }
    }

    public func setGroupMembers(_ playerIDs: [String], group id: String) async throws {
        try await groupCommand(id) { try await api.setGroupMembers(playerIDs, groupID: id, at: $0) }
    }

    public func setPlayerVolume(_ level: Int, player id: String) async throws {
        try await api.setPlayerVolume(level, playerID: id, at: playerAddress(id))
    }

    public func setPlayerMuted(_ muted: Bool, player id: String) async throws {
        try await api.setPlayerMuted(muted, playerID: id, at: playerAddress(id))
    }

    public func eq(player id: String) async throws -> EQSettings {
        let player = try requirePlayer(id)
        return try await upnp.eqSettings(address: player.address, hasSub: player.hasSub)
    }

    public func setEQ(_ eq: EQSettings, player id: String) async throws {
        try await upnp.apply(eq, address: playerAddress(id))
    }

    // MARK: Discovery handling

    private func handle(discovery event: DiscoveryEvent) async {
        switch event {
        case .found(let player):
            addresses[player.id] = player.address
            trustStore?.allow(host: player.address)
            if gatewayID == nil {
                gatewayID = player.id
                timeoutTask?.cancel()
                await refreshTopology()
                await refreshFavorites()
            }
        case .lost(let playerID):
            apply(.playerRemoved(playerID: playerID))
            await stopSocket(playerID)
            if gatewayID == playerID { gatewayID = snapshot.players.first?.id }
            await reconcileSubscriptions()
        case .permissionDenied:
            apply(.status(.localNetworkDenied))
        }
    }

    private func discoveryTimedOut() {
        if snapshot.players.isEmpty, snapshot.status == .discovering {
            apply(.status(.noPlayersFound))
        }
    }

    // MARK: REST refreshes

    private func refreshTopology() async {
        guard let gateway = gatewayAddress() else { return }
        do {
            let response = try await api.groups(from: gateway)
            apply(.topology(groups: response.groups, players: response.players))
            for player in snapshot.players {
                addresses[player.id] = player.address
                trustStore?.allow(host: player.address)
            }
            if snapshot.status != .ready { apply(.status(.ready)) }
            await ensureSockets()
            await reconcileSubscriptions()
            await probeSubs()
        } catch LocalAPIError.invalidAPIKey, LocalAPIError.unauthorized {
            apply(.status(.unauthorized))
        } catch {
            // Keep the previous snapshot; the next socket event or command will retry.
        }
    }

    private func refreshFavorites() async {
        guard let gateway = gatewayAddress() else { return }
        if let favorites = try? await api.favorites(from: gateway) {
            apply(.favorites(favorites))
        }
    }

    private func probeSubs() async {
        for player in snapshot.players where !subProbed.contains(player.id) {
            subProbed.insert(player.id)
            let hasSub = (try? await upnp.hasSub(address: player.address)) ?? false
            apply(.playerHasSub(playerID: player.id, hasSub: hasSub))
        }
    }

    // MARK: Sockets

    private func ensureSockets() async {
        let wanted = Set(snapshot.players.map(\.id))
        for id in Set(sockets.keys).subtracting(wanted) {
            await stopSocket(id)
        }
        for player in snapshot.players where sockets[player.id] == nil {
            let socket = PlayerSocket(playerID: player.id, address: player.address, transport: transport, backoff: configuration.backoff)
            sockets[player.id] = socket
            socketTasks[player.id] = Task { [weak self] in
                for await output in socket.outputs {
                    guard let self else { return }
                    await self.handle(socketOutput: output, from: player.id)
                }
            }
            await socket.start()
        }
    }

    private func stopSocket(_ playerID: String) async {
        socketTasks[playerID]?.cancel()
        socketTasks[playerID] = nil
        if let socket = sockets.removeValue(forKey: playerID) {
            await socket.stop()
        }
    }

    private func reconcileSubscriptions() async {
        let plan = SubscriptionPlan.make(groups: snapshot.groups, players: snapshot.players, gatewayID: gatewayID)
        for (id, socket) in sockets {
            await socket.setSubscriptions(plan[id] ?? [])
        }
    }

    private func handle(socketOutput output: PlayerSocket.Output, from playerID: String) async {
        guard case .event(let event) = output else { return }
        switch event {
        case .playbackStatus(let groupID, let state):
            apply(.playbackStatus(groupID: groupID, state: state))
        case .metadata(let groupID, let nowPlaying):
            apply(.metadata(groupID: groupID, nowPlaying: nowPlaying))
        case .groupVolume(let groupID, let volume):
            apply(.groupVolume(groupID: groupID, volume: volume))
        case .playerVolume(let id, let volume):
            apply(.playerVolume(playerID: id, volume: volume))
        case .groups(let groups, let players):
            apply(.topology(groups: groups, players: players))
            for player in snapshot.players {
                addresses[player.id] = player.address
                trustStore?.allow(host: player.address)
            }
            await ensureSockets()
            await reconcileSubscriptions()
            await probeSubs()
        case .favoritesChanged:
            await refreshFavorites()
        case .subscribed, .globalError, .unknown:
            break
        }
    }

    // MARK: Helpers

    private func apply(_ event: HouseholdEvent) {
        snapshot = SnapshotReducer.reduce(snapshot, event)
        for continuation in observers.values {
            continuation.yield(snapshot)
        }
    }

    private func removeObserver(_ id: UUID) {
        observers[id] = nil
    }

    private func gatewayAddress() -> String? {
        guard let gatewayID else { return nil }
        return addresses[gatewayID]
    }

    private func requirePlayer(_ id: String) throws -> Player {
        guard let player = snapshot.player(id) else { throw HouseholdError.unknownPlayer }
        return player
    }

    private func playerAddress(_ id: String) throws -> String {
        try requirePlayer(id).address
    }

    private func coordinatorAddress(for groupID: String) -> String? {
        guard let group = snapshot.group(groupID) else { return nil }
        return snapshot.player(group.coordinatorID)?.address ?? addresses[group.coordinatorID]
    }

    /// Runs `operation` against the coordinator; on a coordinator change, refreshes topology and retries once.
    private func groupCommand(_ groupID: String, _ operation: (String) async throws -> Void) async throws {
        guard let address = coordinatorAddress(for: groupID) else { throw HouseholdError.unknownGroup }
        do {
            try await operation(address)
        } catch LocalAPIError.coordinatorMoved, LocalAPIError.groupGone {
            await refreshTopology()
            guard let retryAddress = coordinatorAddress(for: groupID) else { throw HouseholdError.unknownGroup }
            try await operation(retryAddress)
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
swift test --filter HouseholdTests 2>&1 | tail -5
```
Expected: `9 tests passed`. Common fixes: if the compiler complains that `operation` escapes in `groupCommand`, mark the parameter `@Sendable` or wrap the body in a nested func. If `discoveryLeadsToReadySnapshotSocketsAndSubscriptions` flakes on `sentText.count`, remember sockets send subscriptions asynchronously; the `waitUntil` calls exist for that reason.

- [ ] **Step 5: Run the full package suite**

```bash
swift test 2>&1 | tail -3
```
Expected: all tests pass (around 49).

- [ ] **Step 6: Commit**

```bash
git add Packages/SonosKit
git commit -m "feat(sonoskit): add Household actor orchestrating discovery, sockets and commands"
```

---
### Task 12: sonosctl command-line tool (manual integration check)

**Files:**
- Delete: `Packages/SonosKit/Sources/sonosctl/main.swift` (a file named main.swift cannot hold `@main`)
- Create: `Packages/SonosKit/Sources/sonosctl/Sonosctl.swift`

**Interfaces:**
- Consumes: `Household`, `BonjourDiscovery`, `URLSessionTransport`.
- Produces: a CLI with `list`, `play|pause|next|prev <room>`, `volume <room> <0-100>`, `eq <room>`, `watch`. `<room>` matches a group name or a player name, case-insensitively, by prefix.

This task has no unit tests; it is the manual integration check against the real speakers. The first Bonjour browse from Terminal triggers the macOS Local Network prompt for Terminal; accept it.

- [ ] **Step 1: Write the tool**

```bash
git rm -q Packages/SonosKit/Sources/sonosctl/main.swift
```

`Packages/SonosKit/Sources/sonosctl/Sonosctl.swift`:
```swift
import Foundation
import SonosKit

let usage = """
sonosctl list
sonosctl play|pause|next|prev <room>
sonosctl volume <room> <0-100>
sonosctl eq <room>
sonosctl watch
"""

@main
struct Sonosctl {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard let command = arguments.first else { print(usage); exit(2) }

        let transport = URLSessionTransport()
        let household = Household(discovery: BonjourDiscovery(), transport: transport, trustStore: transport.trustStore)
        let stream = await household.snapshots()
        await household.start()

        // Wait for discovery to settle, then give the websockets a moment to push current state.
        for await snapshot in stream {
            switch snapshot.status {
            case .ready where !snapshot.groups.isEmpty:
                break
            case .noPlayersFound:
                print("No Sonos found on this network."); exit(1)
            case .unauthorized:
                print("Authentication is switched on in the Sonos app; turn it off under connection security."); exit(1)
            case .localNetworkDenied:
                print("Local Network permission denied. System Settings → Privacy & Security → Local Network."); exit(1)
            case .discovering, .ready:
                continue
            }
            break
        }
        try? await Task.sleep(for: .seconds(1.5))
        let snapshot = await household.current

        func group(named name: String) -> Group? {
            let needle = name.lowercased()
            if let byGroup = snapshot.groups.first(where: { $0.name.lowercased().hasPrefix(needle) }) { return byGroup }
            if let player = snapshot.players.first(where: { $0.name.lowercased().hasPrefix(needle) }) {
                return snapshot.group(containing: player.id)
            }
            return nil
        }

        do {
            switch command {
            case "list":
                for g in snapshot.groups {
                    let track = g.nowPlaying.map { "\($0.title) — \($0.artist ?? "")" } ?? "—"
                    print("\(g.name) [\(g.playbackState)] vol \(g.volume.level)\(g.volume.muted ? " muted" : "")  \(track)")
                    for id in g.playerIDs {
                        let player = snapshot.player(id)
                        let volume = snapshot.playerVolumes[id]?.level ?? -1
                        print("    \(player?.name ?? id) @ \(player?.address ?? "?") vol \(volume)\(player?.hasSub == true ? " +sub" : "")")
                    }
                }
            case "play", "pause", "next", "prev":
                guard let target = group(named: arguments.dropFirst().joined(separator: " ")) else { print("No such room"); exit(1) }
                switch command {
                case "play": try await household.play(group: target.id)
                case "pause": try await household.pause(group: target.id)
                case "next": try await household.next(group: target.id)
                default: try await household.previous(group: target.id)
                }
                print("ok: \(command) \(target.name)")
            case "volume":
                guard arguments.count >= 3, let level = Int(arguments[arguments.count - 1]),
                      let target = group(named: arguments[1..<(arguments.count - 1)].joined(separator: " ")) else { print(usage); exit(2) }
                try await household.setGroupVolume(level, group: target.id)
                print("ok: \(target.name) volume \(level)")
            case "eq":
                guard let target = group(named: arguments.dropFirst().joined(separator: " ")) else { print("No such room"); exit(1) }
                for id in target.playerIDs {
                    let eq = try await household.eq(player: id)
                    print("\(snapshot.player(id)?.name ?? id): bass \(eq.bass) treble \(eq.treble) loudness \(eq.loudness) sub \(eq.subGain.map(String.init) ?? "n/a")")
                }
            case "watch":
                print("Watching events, Ctrl-C to stop…")
                for await snapshot in await household.snapshots() {
                    let line = snapshot.groups.map { "\($0.name):\($0.playbackState.rawValue.replacingOccurrences(of: "PLAYBACK_STATE_", with: "")):\($0.volume.level)" }.joined(separator: "  ")
                    print(Date.now.formatted(date: .omitted, time: .standard), line)
                }
            default:
                print(usage); exit(2)
            }
        } catch {
            print("error: \(error)"); exit(1)
        }
        await household.stop()
        exit(0)
    }
}
```

- [ ] **Step 2: Build and run against the real system**

```bash
swift build 2>&1 | tail -2
swift run sonosctl list
```
(The `watch` command uses `for await snapshot in await household.snapshots()`; the `await` on the stream creation is required because `snapshots()` is an actor method.)
Expected: the rooms print with their addresses and states, for example `Flyttbar + 1 [playing] vol 5` with two indented players. If it prints "No Sonos found", check System Settings → Privacy & Security → Local Network for Terminal. Then, with something playing: `swift run sonosctl volume stereo 8` then `swift run sonosctl volume stereo 5`. Both must print `ok`. Then `swift run sonosctl eq stereo` must print bass, treble, loudness, and sub for the Amp.

- [ ] **Step 3: Record the outcome and commit**

Add a line to `knowledge/ERRORS.md` only if something failed. Update `changelog.md` under Unreleased/Added: "sonosctl CLI for manual checks (list, play, pause, next, prev, volume, eq, watch)."

```bash
git add Packages/SonosKit changelog.md knowledge
git commit -m "feat(sonosctl): add manual integration CLI"
```

---

### Task 13: App scaffold with XcodeGen and MenuBarExtra

**Files:**
- Create: `project.yml`
- Create: `SonosRemote/App/SonosRemoteApp.swift`
- Create: `SonosRemote/App/PanelController.swift`
- Create: `SonosRemote/App/AppState.swift` (minimal; grows in Task 14)
- Create: `SonosRemote/Views/PanelView.swift` (placeholder list; replaced in Task 15)
- Create: `SonosRemote/Views/SettingsView.swift` (placeholder; completed in Task 19)
- Create: `SonosRemoteTests/SmokeTests.swift`
- Modify: `.gitignore` (already ignores `*.xcodeproj`, `.build/`; verify)

**Interfaces:**
- Consumes: `Household`, `BonjourDiscovery`, `URLSessionTransport`, `HouseholdSnapshot`.
- Produces: `@MainActor @Observable final class AppState { static func live() -> AppState; init(household: Household); var snapshot: HouseholdSnapshot; func start() }`, `@MainActor @Observable final class PanelController { var isPresented: Bool; func toggle() }`, `extension KeyboardShortcuts.Name { static let togglePanel }`.

- [ ] **Step 1: Write project.yml**

```yaml
name: SonosRemote
options:
  bundleIdPrefix: com.jenswedin
  deploymentTarget:
    macOS: "26.0"
  createIntermediateGroups: true
  generateEmptyDirectories: true
packages:
  SonosKit:
    path: Packages/SonosKit
  MenuBarExtraAccess:
    url: https://github.com/orchetect/MenuBarExtraAccess
    from: 1.3.0
  KeyboardShortcuts:
    url: https://github.com/sindresorhus/KeyboardShortcuts
    from: 3.0.0
settings:
  base:
    SWIFT_VERSION: "6.0"
    SWIFT_STRICT_CONCURRENCY: complete
    MACOSX_DEPLOYMENT_TARGET: "26.0"
    CODE_SIGN_STYLE: Manual
    CODE_SIGN_IDENTITY: "-"
    DEVELOPMENT_TEAM: ""
    ENABLE_HARDENED_RUNTIME: NO
targets:
  SonosRemote:
    type: application
    platform: macOS
    sources:
      - path: SonosRemote
    entitlements:
      path: SonosRemote/SonosRemote.entitlements
      properties:
        com.apple.security.app-sandbox: true
        com.apple.security.network.client: true
    info:
      path: SonosRemote/Info.plist
      properties:
        CFBundleDisplayName: Sonos Remote
        CFBundleName: Sonos Remote
        LSUIElement: true
        LSMinimumSystemVersion: "26.0"
        NSLocalNetworkUsageDescription: Sonos Remote finds and controls your Sonos speakers on the local network.
        NSBonjourServices:
          - _sonos._tcp
        NSAppTransportSecurity:
          NSAllowsLocalNetworking: true
    dependencies:
      - package: SonosKit
      - package: MenuBarExtraAccess
      - package: KeyboardShortcuts
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.jenswedin.SonosRemote
        GENERATE_INFOPLIST_FILE: NO
  SonosRemoteTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: SonosRemoteTests
    dependencies:
      - target: SonosRemote
schemes:
  SonosRemote:
    build:
      targets:
        SonosRemote: all
        SonosRemoteTests: [test]
    run:
      config: Debug
    test:
      config: Debug
      targets:
        - SonosRemoteTests
```

Ad-hoc signing (`CODE_SIGN_IDENTITY: "-"`) lets the app run locally with the sandbox entitlement and needs no Apple account. Because ad-hoc signatures change per build, macOS may re-ask the Local Network permission after rebuilds. To stop that later, set `DEVELOPMENT_TEAM` to the Personal Team id from `security find-identity -v -p codesigning` and `CODE_SIGN_IDENTITY: "Apple Development"`, `CODE_SIGN_STYLE: Automatic`.

- [ ] **Step 2: Write the app entry, panel controller, and minimal state**

`SonosRemote/App/PanelController.swift`:
```swift
import Observation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let togglePanel = Self("togglePanel")
}

/// Bridges MenuBarExtraAccess's isPresented binding with the global shortcut and Escape.
@MainActor @Observable
final class PanelController {
    var isPresented = false

    func toggle() { isPresented.toggle() }
    func close() { isPresented = false }
}
```

`SonosRemote/App/AppState.swift` (minimal for now):
```swift
import Foundation
import Observation
import SonosKit

@MainActor @Observable
final class AppState {
    private(set) var snapshot = HouseholdSnapshot()
    let household: Household
    private var consumeTask: Task<Void, Never>?

    init(household: Household) {
        self.household = household
    }

    static func live() -> AppState {
        let transport = URLSessionTransport()
        let household = Household(discovery: BonjourDiscovery(), transport: transport, trustStore: transport.trustStore)
        return AppState(household: household)
    }

    func start() {
        guard consumeTask == nil else { return }
        consumeTask = Task { [household] in
            await household.start()
            for await snapshot in await household.snapshots() {
                self.apply(snapshot)
            }
        }
    }

    func apply(_ snapshot: HouseholdSnapshot) {
        self.snapshot = snapshot
    }
}
```

`SonosRemote/App/SonosRemoteApp.swift`:
```swift
import SwiftUI
import SonosKit
import MenuBarExtraAccess
import KeyboardShortcuts

@main
struct SonosRemoteApp: App {
    @State private var appState = AppState.live()
    @State private var panel = PanelController()

    init() {
        let panel = PanelController()
        _panel = State(initialValue: panel)
        KeyboardShortcuts.onKeyUp(for: .togglePanel) {
            Task { @MainActor in panel.toggle() }
        }
    }

    var body: some Scene {
        MenuBarExtra("Sonos", systemImage: "hifispeaker.2") {
            PanelView(closePanel: { panel.close() })
                .environment(appState)
                .environment(panel)
                .onAppear { appState.start() }
        }
        .menuBarExtraStyle(.window)
        .menuBarExtraAccess(isPresented: $panel.isPresented)

        Settings {
            SettingsView()
        }
    }
}
```

`SonosRemote/Views/PanelView.swift` (placeholder, replaced in Task 15):
```swift
import SwiftUI
import SonosKit

struct PanelView: View {
    @Environment(AppState.self) private var state
    let closePanel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sonos").font(.headline)
            Text(String(describing: state.snapshot.status)).foregroundStyle(.secondary)
            ForEach(state.snapshot.groups) { group in
                Text("\(group.name) · \(group.playbackState.rawValue)")
            }
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .padding(12)
        .frame(width: 340)
        .onExitCommand(perform: closePanel)
    }
}
```

`SonosRemote/Views/SettingsView.swift` (placeholder, completed in Task 19):
```swift
import SwiftUI

struct SettingsView: View {
    var body: some View {
        Text("Settings arrive in a later task").padding()
    }
}
```

`SonosRemoteTests/SmokeTests.swift`:
```swift
import Testing
@testable import SonosRemote

@Suite struct SmokeTests {
    @Test @MainActor func panelControllerToggles() {
        let panel = PanelController()
        #expect(!panel.isPresented)
        panel.toggle()
        #expect(panel.isPresented)
        panel.close()
        #expect(!panel.isPresented)
    }
}
```

- [ ] **Step 3: Generate, build, test, run**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate 2>&1 | tail -2
xcodebuild -project SonosRemote.xcodeproj -scheme SonosRemote -configuration Debug -derivedDataPath .build/xcode build 2>&1 | grep -E "error:|warning: .*Swift|BUILD" | head -20
xcodebuild test -project SonosRemote.xcodeproj -scheme SonosRemote -destination 'platform=macOS' -derivedDataPath .build/xcode 2>&1 | grep -E "error:|Test Suite|passed|failed" | tail -6
pkill -x SonosRemote; open .build/xcode/Build/Products/Debug/SonosRemote.app
```
Expected: `BUILD SUCCEEDED`, the smoke test passes, a speaker icon appears in the menu bar with no Dock icon, clicking it shows the status and after a few seconds the group names. macOS asks for Local Network permission on first launch; allow it. If the first package resolution fails offline, run `xcodebuild -resolvePackageDependencies -project SonosRemote.xcodeproj` once.

- [ ] **Step 4: Commit**

```bash
git add project.yml SonosRemote SonosRemoteTests .gitignore
git commit -m "feat(app): scaffold menu bar app with XcodeGen and live household"
```

---

### Task 14: App state logic: row open policy, volume command gate, commands

**Files:**
- Create: `SonosRemote/App/RowOpenPolicy.swift`
- Create: `SonosRemote/App/VolumeCommandGate.swift`
- Modify: `SonosRemote/App/AppState.swift` (replace whole file)
- Test: `SonosRemoteTests/RowOpenPolicyTests.swift`
- Test: `SonosRemoteTests/VolumeCommandGateTests.swift`

**Interfaces:**
- Produces:
  - `enum RowOpenPolicy { static func resolve(remembered: String?, groups: [Group]) -> String? }`
  - `struct VolumeCommandGate { init(minimumInterval: TimeInterval = 0.1, suppressIncomingFor: TimeInterval = 0.5); mutating func userChanged(to value: Int, at now: Date) -> Int?; mutating func flush(at now: Date) -> Int?; func shouldAcceptIncoming(at now: Date) -> Bool; var hasPending: Bool }`
  - `AppState` additions: `var openGroupID: String?`, `enum OpenRowTab { case favorites, eq, group }`, `var selectedTab: OpenRowTab`, `var rowErrors: [String: String]`, `var eqByPlayer: [String: EQSettings]`, `var eqPlayerID: String?`, `func toggleRow(_ groupID: String)`, `func play/pause/next/previous(group:)`, `func togglePlayPause(group:)`, `func setGroupVolume(_:group:)`, `func setGroupMuted(_:group:)`, `func setPlayerVolume(_:player:)`, `func setPlayerMuted(_:player:)`, `func playFavorite(_:group:)`, `func setMembership(of player: String, inGroup: String, member: Bool)`, `func loadEQ(player:)`, `func updateEQ(_:player:)`.

Row-open rule (spec §5): keep the open row if it still exists; if it vanished or nothing has been resolved yet, pick the remembered id when present, else the first playing group, else the first group. If the user explicitly closed the row (set to nil) it stays closed until the topology changes.

- [ ] **Step 1: Write the failing tests**

`SonosRemoteTests/RowOpenPolicyTests.swift`:
```swift
import Testing
import SonosKit
@testable import SonosRemote

@Suite struct RowOpenPolicyTests {
    func group(_ id: String, _ state: PlaybackState) -> Group {
        Group(id: id, name: id, coordinatorID: id, playerIDs: [id], playbackState: state, volume: .silent, nowPlaying: nil)
    }

    @Test func remembered_wins_when_it_exists() {
        let groups = [group("a", .idle), group("b", .playing)]
        #expect(RowOpenPolicy.resolve(remembered: "a", groups: groups) == "a")
    }

    @Test func first_playing_when_remembered_is_gone() {
        let groups = [group("a", .idle), group("b", .playing), group("c", .playing)]
        #expect(RowOpenPolicy.resolve(remembered: "zzz", groups: groups) == "b")
        #expect(RowOpenPolicy.resolve(remembered: nil, groups: groups) == "b")
    }

    @Test func first_group_when_nothing_plays() {
        let groups = [group("a", .idle), group("b", .paused)]
        #expect(RowOpenPolicy.resolve(remembered: nil, groups: groups) == "a")
    }

    @Test func nil_when_no_groups() {
        #expect(RowOpenPolicy.resolve(remembered: "a", groups: []) == nil)
    }
}
```

`SonosRemoteTests/VolumeCommandGateTests.swift`:
```swift
import Foundation
import Testing
@testable import SonosRemote

@Suite struct VolumeCommandGateTests {
    let t0 = Date(timeIntervalSince1970: 1_000)

    @Test func firstChangeSendsImmediately() {
        var gate = VolumeCommandGate()
        #expect(gate.userChanged(to: 10, at: t0) == 10)
        #expect(!gate.hasPending)
    }

    @Test func rapidChangesAreCoalescedUntilTheIntervalPasses() {
        var gate = VolumeCommandGate(minimumInterval: 0.1, suppressIncomingFor: 0.5)
        #expect(gate.userChanged(to: 10, at: t0) == 10)
        #expect(gate.userChanged(to: 11, at: t0.addingTimeInterval(0.02)) == nil)
        #expect(gate.userChanged(to: 12, at: t0.addingTimeInterval(0.05)) == nil)
        #expect(gate.hasPending)
        #expect(gate.flush(at: t0.addingTimeInterval(0.08)) == nil)
        #expect(gate.flush(at: t0.addingTimeInterval(0.11)) == 12)
        #expect(!gate.hasPending)
        #expect(gate.flush(at: t0.addingTimeInterval(0.5)) == nil)
    }

    @Test func changeAfterIntervalSendsDirectly() {
        var gate = VolumeCommandGate(minimumInterval: 0.1, suppressIncomingFor: 0.5)
        _ = gate.userChanged(to: 10, at: t0)
        #expect(gate.userChanged(to: 20, at: t0.addingTimeInterval(0.2)) == 20)
    }

    @Test func incomingIsSuppressedShortlyAfterASend() {
        var gate = VolumeCommandGate(minimumInterval: 0.1, suppressIncomingFor: 0.5)
        #expect(gate.shouldAcceptIncoming(at: t0))
        _ = gate.userChanged(to: 10, at: t0)
        #expect(!gate.shouldAcceptIncoming(at: t0.addingTimeInterval(0.3)))
        #expect(gate.shouldAcceptIncoming(at: t0.addingTimeInterval(0.5)))
    }
}
```

- [ ] **Step 2: Run to verify failure**

```bash
xcodebuild test -project SonosRemote.xcodeproj -scheme SonosRemote -destination 'platform=macOS' -derivedDataPath .build/xcode 2>&1 | grep -E "error:" | head -5
```
Expected: `cannot find 'RowOpenPolicy'`, `cannot find 'VolumeCommandGate'`. (Re-run `xcodegen generate` first whenever files are added.)

- [ ] **Step 3: Write the two pure types**

`SonosRemote/App/RowOpenPolicy.swift`:
```swift
import SonosKit

enum RowOpenPolicy {
    static func resolve(remembered: String?, groups: [Group]) -> String? {
        if let remembered, groups.contains(where: { $0.id == remembered }) { return remembered }
        if let playing = groups.first(where: { $0.playbackState == .playing }) { return playing.id }
        return groups.first?.id
    }
}
```

`SonosRemote/App/VolumeCommandGate.swift`:
```swift
import Foundation

/// Throttles slider sends to one per `minimumInterval` and suppresses incoming volume events
/// for `suppressIncomingFor` after a send so the thumb does not jump back under the cursor.
struct VolumeCommandGate {
    var minimumInterval: TimeInterval
    var suppressIncomingFor: TimeInterval
    private(set) var lastSent: Date?
    private(set) var pending: Int?

    init(minimumInterval: TimeInterval = 0.1, suppressIncomingFor: TimeInterval = 0.5) {
        self.minimumInterval = minimumInterval
        self.suppressIncomingFor = suppressIncomingFor
    }

    var hasPending: Bool { pending != nil }

    /// Returns the value to send now, or nil if it was queued.
    mutating func userChanged(to value: Int, at now: Date) -> Int? {
        if let lastSent, now.timeIntervalSince(lastSent) < minimumInterval {
            pending = value
            return nil
        }
        lastSent = now
        pending = nil
        return value
    }

    /// Returns a queued value once the interval has passed, else nil.
    mutating func flush(at now: Date) -> Int? {
        guard let value = pending else { return nil }
        if let lastSent, now.timeIntervalSince(lastSent) < minimumInterval { return nil }
        lastSent = now
        pending = nil
        return value
    }

    func shouldAcceptIncoming(at now: Date) -> Bool {
        guard let lastSent else { return true }
        return now.timeIntervalSince(lastSent) >= suppressIncomingFor
    }
}
```

- [ ] **Step 4: Replace AppState with the full version**

`SonosRemote/App/AppState.swift`:
```swift
import Foundation
import Observation
import SonosKit

enum OpenRowTab: String, CaseIterable, Identifiable {
    case favorites, eq, group
    var id: String { rawValue }
    var title: String {
        switch self {
        case .favorites: "Favorites"
        case .eq: "EQ"
        case .group: "Group"
        }
    }
}

@MainActor @Observable
final class AppState {
    private(set) var snapshot = HouseholdSnapshot()
    /// The one open row. nil only when the user closed it or nothing is discovered.
    var openGroupID: String? {
        didSet { defaults.set(openGroupID, forKey: Self.openGroupKey) }
    }
    var selectedTab: OpenRowTab = .favorites
    /// Player whose EQ the EQ tab shows (matters for multi-player groups).
    var eqPlayerID: String?
    var eqByPlayer: [String: EQSettings] = [:]
    var rowErrors: [String: String] = [:]

    /// Replaced by `retryDiscovery()` (Task 18); everything else reads it at call time.
    private(set) var household: Household
    private let defaults: UserDefaults
    private var consumeTask: Task<Void, Never>?
    private var resolvedInitialRow = false
    private static let openGroupKey = "openGroupID"

    init(household: Household, defaults: UserDefaults = .standard) {
        self.household = household
        self.defaults = defaults
        self.openGroupID = defaults.string(forKey: Self.openGroupKey)
    }

    static func live() -> AppState {
        let transport = URLSessionTransport()
        let household = Household(discovery: BonjourDiscovery(), transport: transport, trustStore: transport.trustStore)
        return AppState(household: household)
    }

    func start() {
        guard consumeTask == nil else { return }
        consumeTask = Task { [household] in
            await household.start()
            for await snapshot in await household.snapshots() {
                self.apply(snapshot)
            }
        }
    }

    func apply(_ snapshot: HouseholdSnapshot) {
        self.snapshot = snapshot
        guard !snapshot.groups.isEmpty else { return }
        let openStillExists = openGroupID.map { id in snapshot.groups.contains { $0.id == id } } ?? false
        if !openStillExists && (!resolvedInitialRow || openGroupID != nil) {
            openGroupID = RowOpenPolicy.resolve(remembered: openGroupID, groups: snapshot.groups)
        }
        resolvedInitialRow = true
        if let open = openGroupID, let group = snapshot.group(open), !group.playerIDs.contains(eqPlayerID ?? "") {
            eqPlayerID = group.coordinatorID
        }
    }

    // MARK: Row state

    func toggleRow(_ groupID: String) {
        if openGroupID == groupID {
            openGroupID = nil
        } else {
            openGroupID = groupID
            eqPlayerID = snapshot.group(groupID)?.coordinatorID
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
        run(id) { try await self.household.setGroupMembers(members, group: id) }
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

    // MARK: Errors

    private func run(_ groupID: String, _ operation: @escaping @Sendable () async throws -> Void) {
        Task {
            do { try await operation() }
            catch { report(groupID, error) }
        }
    }

    private func report(_ groupID: String, _ error: any Error) {
        rowErrors[groupID] = Self.message(for: error)
        Task {
            try? await Task.sleep(for: .seconds(3))
            if rowErrors[groupID] == Self.message(for: error) { rowErrors[groupID] = nil }
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

- [ ] **Step 5: Run the app tests to verify they pass**

```bash
xcodegen generate 2>&1 | tail -1
xcodebuild test -project SonosRemote.xcodeproj -scheme SonosRemote -destination 'platform=macOS' -derivedDataPath .build/xcode 2>&1 | grep -E "error:|Executed|passed|failed" | tail -6
```
Expected: 9 tests passed (1 smoke + 4 + 4).

- [ ] **Step 6: Commit**

```bash
git add SonosRemote SonosRemoteTests
git commit -m "feat(app): add app state with row policy, volume gate and commands"
```

---
### Task 15: Panel list, closed rows, and the live volume slider

**Files:**
- Modify: `SonosRemote/Views/PanelView.swift` (replace whole file)
- Create: `SonosRemote/Views/GroupRowView.swift`
- Create: `SonosRemote/Views/ClosedRowView.swift`
- Create: `SonosRemote/Views/VolumeSliderView.swift`
- Create: `SonosRemote/Views/Artwork.swift`
- Create: `SonosRemote/Views/FooterView.swift`
- Create: `SonosRemote/Views/StatusBannerView.swift` (placeholder text only; full version in Task 18)
- Create: `SonosRemote/Views/OpenRowView.swift` (placeholder; full version in Task 16)

**Interfaces:**
- Consumes: `AppState`, `VolumeCommandGate`, `Group`, `Volume`, `NowPlaying`.
- Produces: `struct VolumeSliderView: View { init(label: String, volume: Volume, accessibilityName: String, indent: Bool = false, onChange: @escaping (Int) -> Void, onMute: @escaping (Bool) -> Void) }`, `struct Artwork: View { init(url: URL?, size: CGFloat) }`, `struct GroupRowView: View { init(group: Group) }`, `struct ClosedRowView: View { init(group: Group) }`, `struct FooterView: View`, `struct StatusBannerView: View`, `struct OpenRowView: View { init(group: Group) }`.

Design facts from the spec: panel 340 pt wide, list scrolls above roughly 560 pt, closed row = artwork 40 pt, name with PLAYING/PAUSED badge, one line of track · artist or "Not playing", and a live group-volume slider. Clicking the row (not the slider) opens it.

- [ ] **Step 1: Write the slider with the gate**

`SonosRemote/Views/VolumeSliderView.swift`:
```swift
import SwiftUI
import SonosKit

/// A labelled 0–100 slider with a mute button. Sends through VolumeCommandGate so dragging
/// does not flood the speaker and incoming events do not fight the thumb.
struct VolumeSliderView: View {
    let label: String
    let volume: Volume
    let accessibilityName: String
    var indent = false
    let onChange: (Int) -> Void
    let onMute: (Bool) -> Void

    @State private var local: Double = 0
    @State private var gate = VolumeCommandGate()
    @State private var flushTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: indent ? 66 : 78, alignment: .leading)
                .padding(.leading, indent ? 12 : 0)
            Slider(value: $local, in: 0...100, step: 1) { editing in
                if !editing { commit(Int(local)) }
            }
            .disabled(volume.fixed)
            .accessibilityLabel("\(accessibilityName) volume")
            .accessibilityValue("\(Int(local)) percent\(volume.muted ? ", muted" : "")")
            .onChange(of: local) { _, newValue in
                if let send = gate.userChanged(to: Int(newValue), at: .now) { onChange(send) } else { scheduleFlush() }
            }
            Text("\(Int(local))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)
                .accessibilityHidden(true)
            Button { onMute(!volume.muted) } label: {
                Image(systemName: volume.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(volume.muted ? "Unmute \(accessibilityName)" : "Mute \(accessibilityName)")
        }
        .onAppear { local = Double(volume.level) }
        .onChange(of: volume.level) { _, incoming in
            if gate.shouldAcceptIncoming(at: .now) { local = Double(incoming) }
        }
    }

    /// Drag ended: send any queued value now if the interval has passed, otherwise the scheduled flush will.
    private func commit(_ value: Int) {
        if let send = gate.flush(at: .now) {
            flushTask?.cancel()
            onChange(send)
        }
    }

    private func scheduleFlush() {
        flushTask?.cancel()
        flushTask = Task {
            try? await Task.sleep(for: .milliseconds(110))
            guard !Task.isCancelled else { return }
            if let send = gate.flush(at: .now) { onChange(send) }
        }
    }
}
```

`SonosRemote/Views/Artwork.swift`:
```swift
import SwiftUI

struct Artwork: View {
    let url: URL?
    let size: CGFloat

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Rectangle().fill(.quaternary)
                    Image(systemName: "music.note").foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size > 48 ? 8 : 6, style: .continuous))
        .accessibilityHidden(true)
    }
}
```

- [ ] **Step 2: Write the closed row, row switch, footer, banner and open-row placeholders**

`SonosRemote/Views/ClosedRowView.swift`:
```swift
import SwiftUI
import SonosKit

struct ClosedRowView: View {
    @Environment(AppState.self) private var state
    let group: Group

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                Artwork(url: group.nowPlaying?.artworkURL, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(group.name).font(.body.weight(.semibold)).lineLimit(1)
                        PlaybackBadge(state: group.playbackState)
                    }
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { state.toggleRow(group.id) }
            VolumeSliderView(
                label: "",
                volume: group.volume,
                accessibilityName: group.name,
                onChange: { state.setGroupVolume($0, group: group.id) },
                onMute: { state.setGroupMuted($0, group: group.id) }
            )
            .frame(width: 130)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(group.name), \(stateDescription), \(subtitle)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Open") { state.toggleRow(group.id) }
    }

    private var subtitle: String {
        guard let now = group.nowPlaying else { return "Not playing" }
        return [now.title, now.artist].compactMap { $0 }.joined(separator: " · ")
    }

    private var stateDescription: String {
        switch group.playbackState {
        case .playing: "playing"
        case .paused: "paused"
        case .buffering: "buffering"
        case .idle: "not playing"
        }
    }
}

struct PlaybackBadge: View {
    let state: PlaybackState

    var body: some View {
        switch state {
        case .playing:
            Text("PLAYING").badgeStyle(.green)
        case .paused:
            Text("PAUSED").badgeStyle(.gray)
        case .buffering:
            Text("LOADING").badgeStyle(.gray)
        case .idle:
            EmptyView()
        }
    }
}

private extension Text {
    func badgeStyle(_ color: Color) -> some View {
        self.font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color, in: RoundedRectangle(cornerRadius: 3))
            .accessibilityHidden(true)
    }
}
```

`SonosRemote/Views/GroupRowView.swift`:
```swift
import SwiftUI
import SonosKit

struct GroupRowView: View {
    @Environment(AppState.self) private var state
    let group: Group

    var body: some View {
        VStack(spacing: 0) {
            if state.openGroupID == group.id {
                OpenRowView(group: group)
            } else {
                ClosedRowView(group: group)
            }
            if let error = state.rowErrors[group.id] {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
                    .accessibilityLabel("Error: \(error)")
            }
        }
        .background(state.openGroupID == group.id ? Color(nsColor: .controlBackgroundColor) : .clear)
        .focusable()
        .onKeyPress(.return) { state.toggleRow(group.id); return .handled }
        .onKeyPress(.space) { state.togglePlayPause(group: group.id); return .handled }
    }
}
```

`SonosRemote/Views/OpenRowView.swift` (placeholder, completed in Task 16):
```swift
import SwiftUI
import SonosKit

struct OpenRowView: View {
    @Environment(AppState.self) private var state
    let group: Group

    var body: some View {
        ClosedRowView(group: group)
    }
}
```

`SonosRemote/Views/StatusBannerView.swift` (placeholder, completed in Task 18):
```swift
import SwiftUI
import SonosKit

struct StatusBannerView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        if state.snapshot.status != .ready {
            Text(String(describing: state.snapshot.status))
                .font(.caption)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
        }
    }
}
```

`SonosRemote/Views/FooterView.swift`:
```swift
import SwiftUI

struct FooterView: View {
    var openSettings: () -> Void

    var body: some View {
        HStack {
            Button("Settings…", action: openSettings)
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .buttonStyle(.borderless)
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}
```

- [ ] **Step 3: Replace PanelView**

`SonosRemote/Views/PanelView.swift`:
```swift
import SwiftUI
import SonosKit

struct PanelView: View {
    @Environment(AppState.self) private var state
    let closePanel: () -> Void
    var openSettings: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Sonos").font(.headline)
                Spacer()
                Text(roomCount).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .accessibilityAddTraits(.isHeader)

            StatusBannerView()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(state.snapshot.groups) { group in
                        Divider()
                        GroupRowView(group: group)
                    }
                }
            }
            .frame(maxHeight: 560)

            Divider()
            FooterView(openSettings: openSettings)
        }
        .frame(width: 340)
        .onExitCommand(perform: closePanel)
    }

    private var roomCount: String {
        let count = state.snapshot.players.count
        return count == 0 ? "" : "\(count) room\(count == 1 ? "" : "s")"
    }
}
```

- [ ] **Step 4: Build, run, and check by hand**

```bash
xcodegen generate 2>&1 | tail -1
xcodebuild -project SonosRemote.xcodeproj -scheme SonosRemote -configuration Debug -derivedDataPath .build/xcode build 2>&1 | grep -E "error:|BUILD" | head
pkill -x SonosRemote; open .build/xcode/Build/Products/Debug/SonosRemote.app
```
Check: every group is a row with art, name, badge, track line and a slider. Drag a slider: the speaker's volume follows (verify with `swift run sonosctl list` in `Packages/SonosKit`) and the thumb does not jump back. Change volume from the Sonos app: the slider follows within a second. Clicking the text of a row highlights it (open view arrives next task). Tab moves focus between rows, Space toggles play on the focused row, Escape closes the panel. VoiceOver reads "Flyttbar + 1, playing, Off the Wall · Michael Jackson".

- [ ] **Step 5: Commit**

```bash
git add SonosRemote
git commit -m "feat(app): render group rows with live volume sliders"
```

---

### Task 16: Open row: header, transport, group and per-player volume, tabs

**Files:**
- Modify: `SonosRemote/Views/OpenRowView.swift` (replace whole file)
- Create: `SonosRemote/Views/TransportView.swift`
- Create: `SonosRemote/Views/FavoritesTabView.swift` (placeholder; completed in Task 17)
- Create: `SonosRemote/Views/EQTabView.swift` (placeholder; completed in Task 17)
- Create: `SonosRemote/Views/GroupTabView.swift` (placeholder; completed in Task 17)

**Interfaces:**
- Consumes: `AppState` (`selectedTab`, `eqPlayerID`, commands), `VolumeSliderView`, `Artwork`, `PlaybackBadge`.
- Produces: `struct TransportView: View { init(group: Group) }`, `struct FavoritesTabView: View { init(group: Group) }`, `struct EQTabView: View { init(group: Group) }`, `struct GroupTabView: View { init(group: Group) }`.

Spec facts: open row shows 64 pt artwork, group name, title, artist · album, service · container; transport previous / play-pause / next; group volume slider; when the group has more than one player, one indented slider per player with mute; then a segmented control Favorites | EQ | Group.

- [ ] **Step 1: Write the transport row**

`SonosRemote/Views/TransportView.swift`:
```swift
import SwiftUI
import SonosKit

struct TransportView: View {
    @Environment(AppState.self) private var state
    let group: Group

    var body: some View {
        HStack(spacing: 26) {
            Button { state.previous(group: group.id) } label: {
                Image(systemName: "backward.fill").font(.title3)
            }
            .accessibilityLabel("Previous track")

            Button { state.togglePlayPause(group: group.id) } label: {
                Image(systemName: group.playbackState == .playing ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(.primary))
                    .foregroundStyle(Color(nsColor: .windowBackgroundColor))
            }
            .accessibilityLabel(group.playbackState == .playing ? "Pause" : "Play")

            Button { state.next(group: group.id) } label: {
                Image(systemName: "forward.fill").font(.title3)
            }
            .accessibilityLabel("Next track")
        }
        .buttonStyle(.borderless)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }
}
```

- [ ] **Step 2: Write the open row and tab placeholders**

`SonosRemote/Views/OpenRowView.swift`:
```swift
import SwiftUI
import SonosKit

struct OpenRowView: View {
    @Environment(AppState.self) private var state
    let group: Group

    var body: some View {
        @Bindable var state = state
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                Artwork(url: group.nowPlaying?.artworkURL, size: 64)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(group.name).font(.body.weight(.semibold)).lineLimit(1)
                        PlaybackBadge(state: group.playbackState)
                    }
                    if let now = group.nowPlaying {
                        Text(now.title).font(.callout.weight(.medium)).lineLimit(1)
                        Text([now.artist, now.album].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        Text([now.serviceName, now.containerName].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    } else {
                        Text("Not playing").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { state.toggleRow(group.id) }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Closes this room")
            }
            .padding(.top, 10)

            TransportView(group: group)

            VolumeSliderView(
                label: group.playerIDs.count > 1 ? "Group" : "Volume",
                volume: group.volume,
                accessibilityName: group.name,
                onChange: { state.setGroupVolume($0, group: group.id) },
                onMute: { state.setGroupMuted($0, group: group.id) }
            )

            if group.playerIDs.count > 1 {
                ForEach(group.playerIDs, id: \.self) { playerID in
                    if let player = state.snapshot.player(playerID) {
                        VolumeSliderView(
                            label: player.name,
                            volume: state.snapshot.playerVolumes[playerID] ?? .silent,
                            accessibilityName: player.name,
                            indent: true,
                            onChange: { state.setPlayerVolume($0, player: playerID) },
                            onMute: { state.setPlayerMuted($0, player: playerID) }
                        )
                    }
                }
            }

            Picker("Section", selection: $state.selectedTab) {
                ForEach(OpenRowTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.top, 4)
            .accessibilityLabel("Section")

            switch state.selectedTab {
            case .favorites: FavoritesTabView(group: group)
            case .eq: EQTabView(group: group)
            case .group: GroupTabView(group: group)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }
}
```

`SonosRemote/Views/FavoritesTabView.swift` (placeholder):
```swift
import SwiftUI
import SonosKit

struct FavoritesTabView: View {
    let group: Group
    var body: some View { Text("Favorites").font(.caption).foregroundStyle(.secondary) }
}
```

`SonosRemote/Views/EQTabView.swift` (placeholder):
```swift
import SwiftUI
import SonosKit

struct EQTabView: View {
    let group: Group
    var body: some View { Text("EQ").font(.caption).foregroundStyle(.secondary) }
}
```

`SonosRemote/Views/GroupTabView.swift` (placeholder):
```swift
import SwiftUI
import SonosKit

struct GroupTabView: View {
    let group: Group
    var body: some View { Text("Group").font(.caption).foregroundStyle(.secondary) }
}
```

- [ ] **Step 3: Build, run, and check by hand**

```bash
xcodegen generate 2>&1 | tail -1
xcodebuild -project SonosRemote.xcodeproj -scheme SonosRemote -configuration Debug -derivedDataPath .build/xcode build 2>&1 | grep -E "error:|BUILD" | head
pkill -x SonosRemote; open .build/xcode/Build/Products/Debug/SonosRemote.app
```
Check: clicking a row opens it and closes the previous one; the open row shows the larger art and three text lines; play/pause toggles the speaker and the badge follows within a second; next/previous skip; a two-player group shows "Group" plus one indented slider per room whose values match the Sonos app; the segmented control switches between the three placeholders; clicking the open row's header closes it. If the `@Bindable var state = state` line fails to compile inside `body`, move it to a computed property `private var bindable: Bindable<AppState> { Bindable(state) }` and use `bindable.selectedTab`.

- [ ] **Step 4: Commit**

```bash
git add SonosRemote
git commit -m "feat(app): add open row with transport, volumes and section tabs"
```

---

### Task 17: Favorites, EQ, and Group tabs

**Files:**
- Modify: `SonosRemote/Views/FavoritesTabView.swift` (replace)
- Modify: `SonosRemote/Views/EQTabView.swift` (replace)
- Modify: `SonosRemote/Views/GroupTabView.swift` (replace)

**Interfaces:**
- Consumes: `AppState.playFavorite`, `AppState.eqByPlayer`, `AppState.eqPlayerID`, `AppState.loadEQ`, `AppState.updateEQ`, `AppState.setMembership`, `EQSettings` ranges, `Player.hasSub`.

Spec facts: Favorites: list with image, name, subtitle; click plays on this group. EQ: room switcher when the group has more than one player; bass and treble −10…10; sub −15…15 only when that player has a sub; loudness as a toggle; double-click a slider to reset it to 0; values read when the tab opens, written on change. Group: "Rooms playing together" with a toggle per household player, coordinator on and disabled, a note under a room currently playing something else.

- [ ] **Step 1: Favorites tab**

`SonosRemote/Views/FavoritesTabView.swift`:
```swift
import SwiftUI
import SonosKit

struct FavoritesTabView: View {
    @Environment(AppState.self) private var state
    let group: Group

    var body: some View {
        VStack(spacing: 0) {
            if state.snapshot.favorites.isEmpty {
                Text("No favorites in your Sonos system yet.")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
            ForEach(state.snapshot.favorites) { favorite in
                Button { state.playFavorite(favorite.id, group: group.id) } label: {
                    HStack(spacing: 10) {
                        Artwork(url: favorite.imageURL, size: 32)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(favorite.name).font(.callout).lineLimit(1)
                            if let subtitle = favorite.subtitle ?? favorite.serviceName {
                                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        Spacer()
                        Image(systemName: "play.fill").foregroundStyle(.tint).font(.caption)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 6)
                .accessibilityLabel("Play \(favorite.name) on \(group.name)")
                Divider()
            }
        }
    }
}
```

- [ ] **Step 2: EQ tab**

`SonosRemote/Views/EQTabView.swift`:
```swift
import SwiftUI
import SonosKit

struct EQTabView: View {
    @Environment(AppState.self) private var state
    let group: Group

    private var players: [Player] { group.playerIDs.compactMap { state.snapshot.player($0) } }
    private var playerID: String { state.eqPlayerID ?? group.coordinatorID }
    private var player: Player? { state.snapshot.player(playerID) }

    var body: some View {
        @Bindable var state = state
        VStack(alignment: .leading, spacing: 6) {
            if players.count > 1 {
                Picker("Room", selection: $state.eqPlayerID) {
                    ForEach(players) { player in
                        Text(player.name).tag(Optional(player.id))
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("Room for EQ")
            }

            if let eq = state.eqByPlayer[playerID], let player {
                EQSlider(label: "Bass", value: eq.bass, range: EQSettings.bassRange, room: player.name) { new in
                    var next = eq; next.bass = new; state.updateEQ(next, player: playerID)
                }
                EQSlider(label: "Treble", value: eq.treble, range: EQSettings.trebleRange, room: player.name) { new in
                    var next = eq; next.treble = new; state.updateEQ(next, player: playerID)
                }
                if player.hasSub, let sub = eq.subGain {
                    EQSlider(label: "Sub", value: sub, range: EQSettings.subGainRange, room: player.name) { new in
                        var next = eq; next.subGain = new; state.updateEQ(next, player: playerID)
                    }
                }
                Toggle("Loudness", isOn: Binding(
                    get: { eq.loudness },
                    set: { on in var next = eq; next.loudness = on; state.updateEQ(next, player: playerID) }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.caption)
                .accessibilityLabel("Loudness for \(player.name)")
            } else {
                HStack { ProgressView().controlSize(.small); Text("Reading EQ…").font(.caption).foregroundStyle(.secondary) }
                    .padding(.vertical, 8)
            }
        }
        .task(id: playerID) { state.loadEQ(player: playerID) }
    }
}

/// Integer slider with a label, a value readout, and double-click-to-zero.
private struct EQSlider: View {
    let label: String
    let value: Int
    let range: ClosedRange<Int>
    let room: String
    let onChange: (Int) -> Void

    @State private var local: Double = 0

    var body: some View {
        HStack(spacing: 8) {
            Text(label).font(.caption).foregroundStyle(.secondary).frame(width: 78, alignment: .leading)
            Slider(value: $local, in: Double(range.lowerBound)...Double(range.upperBound), step: 1) { editing in
                if !editing, Int(local) != value { onChange(Int(local)) }
            }
            .accessibilityLabel("\(label) for \(room)")
            .accessibilityValue("\(Int(local))")
            .onTapGesture(count: 2) { local = 0; onChange(0) }
            Text(Int(local) > 0 ? "+\(Int(local))" : "\(Int(local))")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)
                .accessibilityHidden(true)
        }
        .onAppear { local = Double(value) }
        .onChange(of: value) { _, new in local = Double(new) }
    }
}
```

- [ ] **Step 3: Group tab**

`SonosRemote/Views/GroupTabView.swift`:
```swift
import SwiftUI
import SonosKit

struct GroupTabView: View {
    @Environment(AppState.self) private var state
    let group: Group

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("ROOMS PLAYING TOGETHER")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.vertical, 6)
                .accessibilityAddTraits(.isHeader)
            ForEach(state.snapshot.players) { player in
                let isCoordinator = player.id == group.coordinatorID
                let isMember = group.playerIDs.contains(player.id)
                let elsewhere = state.snapshot.group(containing: player.id)
                let playingElsewhere = !isMember && elsewhere?.playbackState == .playing
                HStack(alignment: .top, spacing: 10) {
                    Toggle(isOn: Binding(
                        get: { isMember },
                        set: { on in state.setMembership(of: player.id, inGroup: group.id, member: on) }
                    )) { EmptyView() }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .disabled(isCoordinator)
                    .accessibilityLabel(membershipLabel(player, isCoordinator: isCoordinator))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(player.name).font(.callout)
                        if isCoordinator {
                            Text("Source of this group").font(.caption).foregroundStyle(.secondary)
                        } else if playingElsewhere, let now = elsewhere?.nowPlaying {
                            Text("Playing \(now.title), will switch to this group").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 6)
                Divider()
            }
        }
    }

    private func membershipLabel(_ player: Player, isCoordinator: Bool) -> String {
        isCoordinator ? "\(player.name), source of this group" : "\(player.name) in \(group.name)"
    }
}
```

- [ ] **Step 4: Build, run, and check by hand**

```bash
xcodegen generate 2>&1 | tail -1
xcodebuild -project SonosRemote.xcodeproj -scheme SonosRemote -configuration Debug -derivedDataPath .build/xcode build 2>&1 | grep -E "error:|BUILD" | head
pkill -x SonosRemote; open .build/xcode/Build/Products/Debug/SonosRemote.app
```
Check, in this order:
1. Favorites: P3 is listed with its image; clicking it starts P3 on the open group (the header updates to P3 · Sveriges Radio).
2. EQ on the Stereo Amp: bass and treble match `swift run sonosctl eq stereo`; the Sub slider is present only for the Amp; moving bass to +3 and running `sonosctl eq stereo` shows 3; double-click resets to 0; loudness toggle flips. On a multi-player group the room switcher changes which player's values show.
3. Group: turning on Sovrum while Flyttbar + 1 is open makes it a three-room group in the Sonos app within two seconds and the row name updates; turning it off releases it. The coordinator's toggle is on and greyed. A room playing elsewhere shows the one-line note.
4. Put everything back the way it was (regroup, EQ values) before committing.

- [ ] **Step 5: Commit**

```bash
git add SonosRemote
git commit -m "feat(app): add favorites, EQ and group tabs"
```

---
### Task 18: Status states, banners, and the keyboard and VoiceOver pass

**Files:**
- Modify: `SonosRemote/Views/StatusBannerView.swift` (replace)
- Modify: `SonosRemote/Views/PanelView.swift` (empty-state rows, arrow-key focus)
- Modify: `SonosRemote/Views/GroupRowView.swift` (focus ring, arrow keys)

**Interfaces:**
- Consumes: `HouseholdStatus`, `AppState.snapshot.status`, `Household.stop()/start()` for retry.
- Produces: `AppState.retryDiscovery()`.

Spec §5 states: discovering → "Looking for Sonos…" row with a progress indicator; no players after the timeout → "No Sonos found on this network" with Retry and a same-network hint; unauthorized → yellow banner about Authentication in the Sonos app; local network denied → banner with the System Settings path. Keyboard: Up/Down move between rows, Return opens/closes, Space toggles play, Escape closes the panel.

- [ ] **Step 1: Add retry to AppState**

Append to `SonosRemote/App/AppState.swift` inside the class, after `start()`. `household` is already `private(set) var` (Task 14) so it can be swapped:
```swift
    /// Tears the household down and starts discovery again (used by the "No Sonos found" state).
    func retryDiscovery() {
        consumeTask?.cancel()
        consumeTask = nil
        resolvedInitialRow = false
        let old = household
        Task { await old.stop() }
        let transport = URLSessionTransport()
        household = Household(discovery: BonjourDiscovery(), transport: transport, trustStore: transport.trustStore)
        snapshot = HouseholdSnapshot()
        start()
    }
```
The command methods already read `self.household` at call time, so they follow the swap automatically.

- [ ] **Step 2: Replace StatusBannerView**

`SonosRemote/Views/StatusBannerView.swift`:
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
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Looking for Sonos…").font(.callout).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .accessibilityElement(children: .combine)
        case .noPlayersFound:
            VStack(alignment: .leading, spacing: 6) {
                Text("No Sonos found on this network").font(.callout.weight(.semibold))
                Text("Your Mac must be on the same Wi‑Fi or wired network as the speakers.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Retry") { state.retryDiscovery() }.controlSize(.small)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        case .unauthorized:
            Banner(
                title: "Authentication is switched on in the Sonos app",
                detail: "Turn it off under Settings → System → Network → Connection security so this app can control your speakers.",
                color: .yellow
            )
        case .localNetworkDenied:
            Banner(
                title: "Local Network access is off",
                detail: "Allow Sonos Remote under System Settings → Privacy & Security → Local Network, then quit and reopen the app.",
                color: .yellow
            )
        }
    }
}

private struct Banner: View {
    let title: String
    let detail: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.callout.weight(.semibold))
            Text(detail).font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 10).padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}
```

- [ ] **Step 3: Arrow-key focus between rows**

In `SonosRemote/Views/PanelView.swift`, add a focus state and pass it down. Replace the `ScrollView` block with:
```swift
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(state.snapshot.groups) { group in
                            Divider()
                            GroupRowView(group: group)
                                .focused($focusedGroupID, equals: group.id)
                                .id(group.id)
                        }
                    }
                }
                .frame(maxHeight: 560)
                .onKeyPress(.downArrow) { move(by: 1); proxy.scrollTo(focusedGroupID); return .handled }
                .onKeyPress(.upArrow) { move(by: -1); proxy.scrollTo(focusedGroupID); return .handled }
            }
```
and add to the struct:
```swift
    @FocusState private var focusedGroupID: String?

    private func move(by offset: Int) {
        let ids = state.snapshot.groups.map(\.id)
        guard !ids.isEmpty else { return }
        guard let current = focusedGroupID, let index = ids.firstIndex(of: current) else {
            focusedGroupID = ids.first
            return
        }
        focusedGroupID = ids[max(0, min(ids.count - 1, index + offset))]
    }
```
In `SonosRemote/Views/GroupRowView.swift` add a visible focus ring so keyboard users can see where they are. Replace the `.focusable()` line with:
```swift
        .focusable()
        .focusEffectDisabled()
        .overlay {
            if isFocused {
                RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor, lineWidth: 2).padding(2)
            }
        }
```
and add `@Environment(\.isFocused) private var isFocused` to the struct.

- [ ] **Step 4: Build, run, and check the states and keyboard**

```bash
xcodegen generate 2>&1 | tail -1
xcodebuild -project SonosRemote.xcodeproj -scheme SonosRemote -configuration Debug -derivedDataPath .build/xcode build 2>&1 | grep -E "error:|BUILD" | head
pkill -x SonosRemote; open .build/xcode/Build/Products/Debug/SonosRemote.app
```
Check:
1. On launch the panel shows "Looking for Sonos…" then the rows.
2. Turn Wi‑Fi off, quit, relaunch: after ~10 s "No Sonos found" appears with Retry; turn Wi‑Fi on, click Retry, rows return.
3. Open the panel, press Down twice: the focus ring moves; Return opens the focused row; Space toggles play on it; Escape closes the panel.
4. With VoiceOver on (⌘F5), VO-Right through a closed row reads name, state, track, then the slider with its value, then the mute button; the open row reads the tab control as a tab group.
5. The unauthorized and denied banners are hard to trigger by hand; verify their layout by temporarily returning `.unauthorized` from a preview or by editing `apply` for one build, then revert.

- [ ] **Step 5: Commit**

```bash
git add SonosRemote
git commit -m "feat(app): add status states, banners, arrow-key focus and focus ring"
```

---

### Task 19: Settings window, launch at login, global shortcut

**Files:**
- Create: `SonosRemote/App/SettingsOpener.swift`
- Modify: `SonosRemote/Views/SettingsView.swift` (replace)
- Modify: `SonosRemote/App/SonosRemoteApp.swift` (wire openSettings)

**Interfaces:**
- Consumes: `KeyboardShortcuts.Name.togglePanel`, `SMAppService`, `PanelController`.
- Produces: `@MainActor final class SettingsOpener { func open() }`, `SettingsView` with launch-at-login toggle and shortcut recorder.

A Dock-less (`LSUIElement`) app cannot reliably show its Settings scene from a menu bar panel on macOS 26 without becoming a regular app first. `SettingsOpener` switches the activation policy to `.regular`, activates, sends the standard `showSettingsWindow:` action, and switches back to `.accessory` when the settings window closes.

- [ ] **Step 1: Write SettingsOpener**

`SonosRemote/App/SettingsOpener.swift`:
```swift
import AppKit

@MainActor
final class SettingsOpener {
    private var observer: (any NSObjectProtocol)?

    func open(closePanel: () -> Void) {
        closePanel()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if !NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
                _ = NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
            }
            self.watchForClose()
        }
    }

    private func watchForClose() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] notification in
            guard let window = notification.object as? NSWindow, window.identifier?.rawValue.contains("Settings") == true || window.title == "Sonos Remote Settings" else { return }
            Task { @MainActor in
                NSApp.setActivationPolicy(.accessory)
                if let observer = self?.observer { NotificationCenter.default.removeObserver(observer) }
                self?.observer = nil
            }
        }
    }
}
```

- [ ] **Step 2: Write the Settings view**

`SonosRemote/Views/SettingsView.swift`:
```swift
import SwiftUI
import ServiceManagement
import KeyboardShortcuts

struct SettingsView: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Toggle("Launch at login", isOn: $launchAtLogin)
                .toggleStyle(.switch)
                .onChange(of: launchAtLogin) { _, on in
                    do {
                        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        loginError = nil
                    } catch {
                        loginError = error.localizedDescription
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
            if let loginError {
                Text(loginError).font(.caption).foregroundStyle(.red)
            }
            KeyboardShortcuts.Recorder("Open panel shortcut", name: .togglePanel)
            Text("Sonos Remote controls your Sonos system over the local network. Nothing leaves your home.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .padding(.vertical, 8)
        .navigationTitle("Sonos Remote Settings")
    }
}
```

- [ ] **Step 3: Wire the footer to the opener**

In `SonosRemote/App/SonosRemoteApp.swift` add `@State private var settingsOpener = SettingsOpener()` and change the `PanelView(...)` line to:
```swift
            PanelView(closePanel: { panel.close() }, openSettings: { settingsOpener.open(closePanel: { panel.close() }) })
```
Give the Settings scene a stable title so the close observer matches: wrap `SettingsView()` as `SettingsView().navigationTitle("Sonos Remote Settings")` (already set inside the view; keeping it here too is harmless).

- [ ] **Step 4: Build, run, check**

```bash
xcodegen generate 2>&1 | tail -1
xcodebuild -project SonosRemote.xcodeproj -scheme SonosRemote -configuration Debug -derivedDataPath .build/xcode build 2>&1 | grep -E "error:|BUILD" | head
pkill -x SonosRemote; open .build/xcode/Build/Products/Debug/SonosRemote.app
```
Check: Settings… opens a window in front; while it is open the app briefly shows in the Dock; closing it removes the Dock icon again. Record ⌃⌥S as the shortcut, close settings, press ⌃⌥S: the panel toggles. Turn "Launch at login" on: System Settings → General → Login Items lists Sonos Remote; turn it off again (or leave it on if Jens wants it). If `showSettingsWindow:` does nothing on this macOS build, log the failure in `knowledge/ERRORS.md` and fall back to opening a plain `Window("Sonos Remote Settings", id: "settings") { SettingsView() }` scene via `@Environment(\.openWindow)`.

- [ ] **Step 5: Commit**

```bash
git add SonosRemote
git commit -m "feat(app): add settings window with launch at login and panel shortcut"
```

---

### Task 20: Documentation, knowledge, and release checklist

**Files:**
- Modify: `README.md`, `changelog.md`, `knowledge/INDEX.md`, `knowledge/procedural/build-and-run.md`
- Create: `knowledge/procedural/manual-test-checklist.md`
- Create: `MEMORY.md` (project-root session memory required by the repository's CLAUDE.md)

- [ ] **Step 1: Update README**

Replace the README's intro and add a "Features" section listing exactly what version 1 does (transport, group and per-speaker volume, grouping, favorites, EQ with sub, launch at login, global shortcut) and a "Not yet" section (media keys, Control Center, queue, search). Add a "How it works" paragraph pointing to `docs/research/2026-09-04-sonos-macos-research.md` and `knowledge/domain/sonos-local-api.md`. Add "Signing" describing ad-hoc signing and the Personal Team switch from Task 13.

- [ ] **Step 2: Write the manual test checklist**

`knowledge/procedural/manual-test-checklist.md`:
```markdown
# Manual test checklist (run before tagging a version)

Preconditions: at least one room playing, one multi-room group, Terminal has Local Network permission.

1. Launch: icon in menu bar, no Dock icon, panel shows "Looking for Sonos…" then all groups within 5 s.
2. Closed rows: art, name, badge, track line, slider. Drag slider → speaker follows; change in Sonos app → slider follows.
3. Open row: click text → opens, previous row closes. Play/pause/next/previous work. Group + per-room sliders on a multi-room group.
4. Favorites: click P3 → plays on the open group.
5. EQ: values match `sonosctl eq <room>`; sub slider only on the Amp; double-click resets; loudness toggles; room switcher on a group.
6. Group: toggle a room on → joins within 2 s; toggle off → releases. Coordinator toggle disabled.
7. Keyboard: Up/Down, Return, Space, Escape; Tab through the open row. VoiceOver reads rows, sliders, toggles, tabs.
8. Errors: Wi‑Fi off at launch → "No Sonos found" + Retry works. Pull the plug on a speaker → its row disappears within 30 s.
9. Settings: opens in front, Dock icon only while open; shortcut records and works; launch at login registers.
10. Quit from the footer.
```

- [ ] **Step 3: Update changelog and knowledge index**

`changelog.md` under `[Unreleased]` → rename to `## [0.1.0] - <today's date>` with Added entries: SonosKit package (discovery, local API client, websocket events, UPnP EQ, Household actor), sonosctl, menu bar app with group rows, open row, favorites, EQ, grouping, status states, settings. Add a fresh empty `[Unreleased]` above it.

`knowledge/INDEX.md`: add the checklist line. `knowledge/procedural/build-and-run.md`: add the "switch to Personal Team" note and the `pkill` tip if not present.

- [ ] **Step 4: Write MEMORY.md**

`MEMORY.md`:
```markdown
# Session memory

Last state: v0.1.0 of Sonos Remote complete per docs/superpowers/plans/2026-09-05-sonos-remote.md. All SonosKit tests and app tests pass; manual checklist in knowledge/procedural/manual-test-checklist.md was run on <date>.

Next ideas (not started): media keys + Control Center now-playing, "show track in menu bar" option, AppKit panel shell for animated resize, Developer ID signing for sharing.
```

- [ ] **Step 5: Run everything one last time, tag, push**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
(cd Packages/SonosKit && swift test 2>&1 | tail -2)
xcodegen generate 2>&1 | tail -1
xcodebuild test -project SonosRemote.xcodeproj -scheme SonosRemote -destination 'platform=macOS' -derivedDataPath .build/xcode 2>&1 | grep -E "passed|failed" | tail -2
git add README.md changelog.md knowledge MEMORY.md
git commit -m "docs: document v0.1.0, add manual test checklist and session memory"
git tag v0.1.0
git push origin main --tags
```

---

## Self-review notes (done while writing)

- Spec coverage: §1 scope → Tasks 15–19; §3 flow → Task 11; §4 SonosKit → Tasks 2–10; §5 panel → Tasks 15–18; §6 concurrency/debounce → Tasks 11, 14, 15; §7 resilience → Tasks 7, 11, 18; §8 testing → every task; §9 mechanics → Tasks 1, 13, 20; §10 risks → knowledge/domain notes in Task 1.
- Deviation from spec §6: artwork uses `AsyncImage` with the default `URLCache` instead of a custom in-memory cache. Add `URLCache.shared = URLCache(memoryCapacity: 20_000_000, diskCapacity: 0)` in `SonosRemoteApp.init()` if images visibly reload; not needed for correctness.
- Deviation from spec §3 step 5: no REST re-fetch of per-group state on reconnect, because the player pushes current state for every namespace immediately after `subscribe` (verified in `events.jsonl`). Topology and favorites are still fetched over REST.
- `favorites:1` events are `versionChanged`, so the favorites list is always re-fetched over REST (Task 11 `refreshFavorites`).
