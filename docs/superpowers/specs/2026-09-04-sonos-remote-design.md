# Sonos Remote for macOS: design spec

Date: 2026-09-04. Status: approved in brainstorming, awaiting written review.

Research behind this spec: `docs/research/2026-09-04-sonos-macos-research.md`.

## 1. Goal

A small, native macOS menu bar app that controls Jens's Sonos S2 system over the local network. Open the panel from the menu bar, see every room and what it is playing, control playback and volume, group rooms, play favorites, and adjust EQ. No Sonos account, no cloud.

### In scope for version 1

- Discover speakers on the local network and stay in sync with them in real time.
- Per group: see now-playing with artwork, play, pause, next, previous, group volume and mute.
- Per speaker inside a group: individual volume and mute.
- Group and ungroup rooms.
- List Sonos favorites and start one on a group.
- EQ per speaker: bass, treble, loudness, and sub level when the speaker has a sub.
- Settings: launch at login, global keyboard shortcut to open the panel.
- Keyboard navigation and VoiceOver support throughout.

### Out of scope for version 1

Media keys and Control Center now-playing, queue editing, browsing music services or search, line-in and TV sources, alarms, sleep timer, S1 systems, distribution to other people, App Store.

## 2. Decisions already made

| Decision | Choice | Why |
|---|---|---|
| Audience | Jens only, on his own Macs | Allows free Personal Team signing, no notarization, and reliance on the undocumented local API |
| Look | Native macOS system look | System controls, SF Symbols, Liquid Glass on macOS 26, accessibility for free |
| Layout | "All rooms, one expands" (layout B) | Whole house at a glance; the opened row carries transport, volume, favorites, EQ, grouping |
| Stack | SwiftUI `MenuBarExtra` window scene plus a local Swift package | First-party, testable from the command line, shell can be swapped for an AppKit panel later without touching views |
| Minimum macOS | 26 | Jens's Macs run 26.5; Liquid Glass and current SwiftUI APIs |
| Sonos transport | Local Control API on HTTPS 1443 (REST + websocket) for everything except EQ; UPnP SOAP on 1400 for EQ | Verified on Jens's speakers; JSON shapes match Sonos's public cloud docs; push events without a callback server |
| Switch style | Toggles everywhere (group membership, loudness) | One switch style across the panel |

## 3. Architecture

Two pieces with a one-way dependency: the app depends on the package, never the reverse.

**SonosKit** (local Swift package, `Packages/SonosKit`). Pure Swift, Foundation and Network only, no AppKit or SwiftUI. Owns discovery, the 1443 REST and websocket client, the 1400 SOAP client, and a `Household` actor that merges everything into immutable snapshots. Includes a small executable target `sonosctl` for manual checks against the real system.

**SonosRemote** (app target). SwiftUI `MenuBarExtra` with `.window` style, one `@MainActor @Observable` app state object, and the panel views. Uses MenuBarExtraAccess for the show/hide binding and KeyboardShortcuts for the global hotkey. The app never touches the network directly.

### Runtime flow

1. On launch, `Household.start()` browses Bonjour for `_sonos._tcp`. Each result yields a player endpoint: IPv4 address, player ID (`RINCON_…`), household ID, and the fact that port 1443 is available.
2. The first discovered player is used as the gateway for household-wide REST calls: groups and players, then favorites.
3. One websocket is opened per player. Every socket subscribes to `playerVolume:1` for its own player. Sockets belonging to group coordinators additionally subscribe to `playback:1`, `playbackMetadata:1`, and `groupVolume:1` for their group. Exactly one socket, the gateway's, subscribes to the household-scoped `groups:1` and `favorites:1`.
4. Every event goes through the reducer, which produces a new snapshot. The app observes the snapshot stream.
5. Commands are one-shot REST calls to the group coordinator, or SOAP calls to the individual player for EQ. After a command the app trusts the next event, not its own optimistic state, except for the slider debounce described in section 6.
6. When a `groups` event changes coordinators or membership, group-scoped subscriptions are dropped and re-issued on the new coordinators.

## 4. SonosKit design

### Public surface

```swift
public actor Household {
    public init(discovery: Discovering = BonjourDiscovery(), transport: Transport = URLSessionTransport())
    public func start() async
    public func stop() async
    public var snapshots: AsyncStream<HouseholdSnapshot>

    public func play(group: Group.ID) async throws
    public func pause(group: Group.ID) async throws
    public func next(group: Group.ID) async throws
    public func previous(group: Group.ID) async throws
    public func setGroupVolume(_ volume: Int, group: Group.ID) async throws
    public func setGroupMuted(_ muted: Bool, group: Group.ID) async throws
    public func setPlayerVolume(_ volume: Int, player: Player.ID) async throws
    public func setPlayerMuted(_ muted: Bool, player: Player.ID) async throws
    public func playFavorite(_ favorite: Favorite.ID, group: Group.ID) async throws
    public func setGroupMembers(_ players: [Player.ID], group: Group.ID) async throws
    public func eq(for player: Player.ID) async throws -> EQSettings
    public func setEQ(_ eq: EQSettings, player: Player.ID) async throws
}
```

### Models

- `HouseholdSnapshot`: `status` (`.discovering`, `.ready`, `.noPlayersFound`, `.unauthorized`), `groups: [Group]`, `players: [Player]`, `favorites: [Favorite]`, `playerVolumes: [Player.ID: Volume]`.
- `Group`: `id`, `name`, `coordinatorID`, `playerIDs`, `playbackState` (`.playing`, `.paused`, `.idle`, `.buffering`), `volume: Volume`, `nowPlaying: NowPlaying?`.
- `Player`: `id`, `name`, `address` (IPv4), `model`, `hasSub: Bool`.
- `Volume`: `level: Int` (0...100), `muted: Bool`, `fixed: Bool`.
- `NowPlaying`: `title`, `artist`, `album`, `artworkURL`, `serviceName`, `containerName`.
- `Favorite`: `id`, `name`, `imageURL`, `serviceName`.
- `EQSettings`: `bass: Int` (−10...10), `treble: Int` (−10...10), `loudness: Bool`, `subGain: Int?` (−15...15, nil when the player has no sub).

`hasSub` is derived at startup by calling `GetEQ SubCrossover` on the player: a non-zero crossover means a sub is attached. On Jens's system only the Amp reports one.

### Internals

- **BonjourDiscovery**: `NWBrowser` for `_sonos._tcp`. Resolves each result to an IPv4 address and reads the TXT record for `uuid`, `hhid`, and `sslport`. Emits additions and removals.
- **LocalAPIClient**: REST over `URLSession`. Base `https://{ip}:1443/api/v1`. Every request carries `X-Sonos-Api-Key: 123e4567-e89b-12d3-a456-426655440000`. Requests are one-shot since players answer `Connection: Close`. Endpoints used: `GET /households/local/groups`, `GET /households/local/favorites`, `GET /groups/{gid}/playbackMetadata`, `GET /groups/{gid}/playback`, `GET /groups/{gid}/groupVolume`, `POST /groups/{gid}/playback/play|pause|skipToNextTrack|skipToPreviousTrack`, `POST /groups/{gid}/groupVolume` and `/groupVolume/mute`, `POST /players/{pid}/playerVolume` and `/playerVolume/mute`, `POST /groups/{gid}/favorites` with `{favoriteId, playOnCompletion: true}`, `POST /groups/{gid}/groups/setGroupMembers` with `{playerIds}`.
- **TrustPolicy**: the session delegate accepts a server-trust challenge only when the host is an IPv4 address in a private range (10/8, 172.16/12, 192.168/16) and the host was produced by discovery. Everything else fails normally. Applies to REST and websocket tasks alike.
- **PlayerSocket**: one `URLSessionWebSocketTask` per player to `wss://{ip}:1443/websocket/api` with subprotocol `v1.api.smartspeaker.audio` and the API key header, no `Origin` header. Messages are JSON arrays `[header, body]`. Outgoing: `[{"namespace": "playback:1", "command": "subscribe", "groupId": gid}, {}]`. Incoming headers carry `namespace`, `type`, and `success`; bodies are decoded by `type` into `playbackStatus`, `metadataStatus`, `groupVolume`, `playerVolume`, `groups`, `favoritesList`. Ping every 30 seconds. On close or error, reconnect with exponential backoff starting at 1 second, doubling, capped at 60 seconds, with jitter. On reconnect, re-subscribe and re-fetch the group's REST state so nothing is missed.
- **UPnPClient**: SOAP POST to `http://{ip}:1400/MediaRenderer/RenderingControl/Control`. Actions `GetBass`, `SetBass`, `GetTreble`, `SetTreble`, `GetLoudness`, `SetLoudness` (channel `Master`), `GetEQ` and `SetEQ` with `EQType` `SubGain` and `SubCrossover`. Response values are extracted with a minimal element-text lookup, not a general XML parser. SOAP fault `402` means the speaker does not support that EQ type and is treated as "not available", not as an error.
- **SnapshotReducer**: a pure function `(HouseholdSnapshot, Event) -> HouseholdSnapshot`. Handles group topology changes, playback state, metadata, group and player volume, favorites list, player addition and removal, and status transitions. No I/O.
- **Transport** protocol: `func send(_ request: Request) async throws -> Response` plus `func openSocket(to: Player) -> SocketStream`. `URLSessionTransport` is the real one; tests use `FakeTransport` with canned fixtures.

### sonosctl

Executable target in the package: `sonosctl list`, `sonosctl play|pause|next|prev <room>`, `sonosctl volume <room> <0-100>`, `sonosctl eq <room>`, `sonosctl watch` (prints events as they arrive). Used for manual integration checks and debugging. Not shipped in the app.

## 5. App design

### Menu bar item

A template SF Symbol (`hifispeaker.2`) and nothing else. It must read on macOS 26's transparent menu bar over busy wallpapers. Clicking toggles the panel. The global shortcut, default unset, toggles it too.

### Panel

340 pt wide. Grows with content up to about 620 pt, then the room list scrolls. Rows are **groups**, not speakers. A grouped set appears as one row named after its members, for example "Stereo + Sovrum", with the coordinator's artwork. Exactly one row is open at a time.

**Header**: "Sonos" and a muted room count.

**Closed row**: artwork or a neutral placeholder, group name with a small PLAYING or PAUSED badge, one line of track and artist or "Not playing", and a live group-volume slider that can be dragged without opening the row. Clicking anywhere else on the row opens it and closes the previously open one.

**Open row**: larger artwork; group name, title, artist and album, and service and container name; transport row with previous, play/pause, next; group volume slider with mute; when the group has more than one player, one indented slider with mute per player; then a segmented control with Favorites, EQ, and Group.

- **Favorites tab**: list of favorites with image, name, and service. Clicking one plays it on this group.
- **EQ tab**: when the group has more than one player, a room switcher above the controls. Bass and treble sliders −10 to 10, sub slider −15 to 15 shown only when that player has a sub, loudness as a toggle. Double-clicking a slider resets it to 0. Values are read when the tab opens and written on change.
- **Group tab**: "Rooms playing together" with one toggle per room in the household. On means the room is in this group. The coordinator's toggle is on and disabled. Turning a room on calls `setGroupMembers` with it added; off with it removed. A room that is currently playing something else shows a one-line note under its name that it will switch to this group.

**Footer**: "Settings…" and "Quit".

### Behaviour

- **Row open on launch**: the last one the user had open, remembered by group ID. If that group no longer exists, the first group that is playing, else the first group. Never none while groups exist.
- **Keyboard**: Up and Down move focus between rows. Return opens or closes the focused row. Space toggles play/pause on the focused row. On a focused slider, Left and Right step by 1 and Shift-arrow by 5. Tab moves through the open row's controls in reading order. Escape closes the panel.
- **VoiceOver**: rows announce group name, playback state, and track. Sliders announce their room and value. The segmented control is a real tab control. Toggles announce room and membership state. Artwork is decorative.
- **Settings window**: launch at login (SMAppService) and a shortcut recorder for the global hotkey. Opened from the footer; the app briefly becomes a regular app to bring the window forward, then returns to accessory.

### Empty and error states

- Discovering: a single row "Looking for Sonos…" with a progress indicator.
- Nothing found after 10 seconds: "No Sonos found on this network" with a Retry button and a hint that the Mac must be on the same network as the speakers.
- Unauthorized (HTTP 401 with `ERROR_NOT_AUTHORIZED`): a yellow banner above the list explaining that "Authentication" is switched on in the Sonos app under connection security settings, and that it must be off for this app to work. The list still shows what it can.
- Command failure: a brief inline message on the affected row, then re-sync from the speaker.
- Websocket down for a player: a small "reconnecting" indicator on affected rows; commands still work through REST.
- Local Network permission denied: a banner explaining how to enable it in System Settings, Privacy & Security, Local Network.

## 6. Data flow and concurrency

- Swift 6 language mode with strict concurrency in both targets.
- `Household` is an actor. `PlayerSocket` instances are owned by it. Discovery and sockets deliver events into a single `AsyncStream<Event>` that the actor consumes serially, so the reducer never races.
- The app state object is `@MainActor @Observable`. It starts one task that iterates `Household.snapshots` and assigns the latest snapshot. Views read from it.
- **Slider debounce**: while a slider is being dragged, the view shows the local value. Commands are sent at most every 100 ms with the latest value. For 500 ms after the last send, incoming volume events for that slider are ignored so the thumb does not jump back. After that, speaker state wins.
- Artwork is loaded with `AsyncImage` and a small in-memory cache keyed by URL.

## 7. Resilience

Summarized from sections 4 and 5: backoff reconnect on socket loss with state re-fetch; REST commands work independently of socket state; coordinators re-subscribed on topology change; 401 detected on the first REST call and surfaced as a status; speaker removal via Bonjour drops its socket and removes it from the snapshot; the app never crashes on an unknown event type, it logs and ignores.

## 8. Testing

Test-first, as the repository's CLAUDE.md asks.

**SonosKit** (Swift Testing, `swift test`, no Xcode GUI needed):

- Fixtures under `Tests/SonosKitTests/Fixtures` are real responses captured from Jens's speakers on 2026-09-03: groups, playbackMetadata, groupVolume, playback, favorites, player info, and the websocket event sequence after subscribe. Personal identifiers such as household ID stay as they are; nothing in them is secret.
- Model decoding for every fixture.
- Reducer: each event type applied to a known snapshot produces the expected snapshot; topology change moves a player between groups and marks coordinators; player removal cleans up.
- Socket framing: encode subscribe commands to the exact JSON array shape; decode `[header, body]` messages by type; unknown types are ignored without error.
- SOAP: envelope building for each EQ action matches the expected XML; response parsing extracts values; fault 402 maps to "not available".
- Backoff schedule: sequence of delays is 1, 2, 4 … capped at 60 with jitter within bounds.
- Trust policy: private IPv4 hosts from discovery are accepted, public hosts and hostnames are rejected.
- Re-subscription: given a groups event that changes coordinators, the actor issues the expected unsubscribe and subscribe commands on the right sockets, verified through `FakeTransport`.

**SonosRemote**: view logic lives in the app state object and is tested with a fake `Household` stream: row open on launch rules, slider debounce timing, error state mapping. Views themselves are checked by hand with VoiceOver and keyboard only. No UI automation in version one.

**Manual integration**: `sonosctl` against the real system before each milestone.

## 9. Project mechanics

- Repository: `jens-wedin/sonos-remote` on GitHub, private.
- Xcode project generated by XcodeGen from `project.yml`. The generated `.xcodeproj` is git-ignored. Build from the command line with `xcodebuild` after `xcode-select` points at Xcode.app.
- Targets: `SonosRemote` app (macOS 26, SwiftUI), `SonosRemoteTests`. Package `Packages/SonosKit` with library, `sonosctl` executable, and tests.
- Dependencies: MenuBarExtraAccess, KeyboardShortcuts. Nothing else.
- Signing: automatic with the Personal Team. App Sandbox enabled with `com.apple.security.network.client` only.
- Info.plist: `LSUIElement` true, `NSLocalNetworkUsageDescription`, `NSBonjourServices` with `_sonos._tcp`, `NSAppTransportSecurity` with `NSAllowsLocalNetworking` true.
- Repository docs: `README.md`, `changelog.md`, `knowledge/INDEX.md` with domain and procedural pages, `knowledge/ERRORS.md`. `.gitignore` covers `.superpowers/`, `*.xcodeproj`, `.build/`, `DerivedData/`, `xcuserdata/`.
- Conventional commits.

## 10. Risks

- **Sonos revokes the placeholder API key or restricts the local API.** No sign of it through firmware 96.x. Mitigation: the transport is isolated behind one protocol, and UPnP already covers transport and volume, so a fallback is a contained change.
- **Authentication toggle in the Sonos app.** Detected and explained in the UI. Default is off.
- **Sonos disables the UPnP endpoint by default in a future update.** EQ would stop working; the rest of the app is unaffected.
- **`MenuBarExtra` window style limitations.** No animated resize when a row opens. Accepted; the AppKit panel shell is the documented upgrade path and the views do not change.
- **Local Network permission state cannot be reset on macOS.** Documented in knowledge as a procedural note for testing on a fresh user account if it goes wrong.

## 11. Later, not now

Media keys and Control Center now-playing, a "show track title in the menu bar" option, queue view, search, sleep timer, the AppKit panel shell, Developer ID signing for sharing.
