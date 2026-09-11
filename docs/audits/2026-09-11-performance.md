# Performance audit — Remote for Sonos

Read-only audit, 2026-09-11. All 59 Swift sources under `SonosRemote/` and
`Packages/SonosKit/Sources/` read in full; 26 test files skimmed for behaviour only.
Nothing was edited, committed, launched, or sent to a speaker.

**Repo:** `/Users/jens.wedin/Sandbox/Code/sonos-remote`

## What was actually measured vs inferred

Everything in this report is **static analysis of the source** unless tagged MEASURED.
The four measured facts:

- **MEASURED** `swift test` in `Packages/SonosKit`: 79 tests, 13 suites, all pass,
  0.174 s test time / 2.10 s wall. No slow or timing-sensitive test.
- **MEASURED** `grep -rn "Connection"` over all `*.swift`: **no `Connection: Close`
  header exists anywhere.** `LocalAPIClient.makeRequest` (`LocalAPIClient.swift:84-91`)
  sets only `X-Sonos-Api-Key` and `Content-Type`. Keep-alive is in effect; the concern
  named in the brief does not apply to this code.
- **MEASURED** `grep -rn "playerVolumes"`: the only readers outside SonosKit itself are
  `sonosctl/Sonosctl.swift:69` and tests. **No view in the app reads it.**
- **MEASURED** `grep -rn "LazyVStack\|LazyHStack\|List("` over `SonosRemote/`:
  **zero matches.** Every list in the app is an eager `VStack`.

Per-event render counts, wakeups/day and image memory are **inferred** from the code
and sized with stated assumptions (5 players, 3 groups, 1 playing, ~100 favourites).
Each finding names what to measure to confirm it.

---

## Findings

Severity counts: **5 High, 11 Medium, 10 Low.**

---

### HIGH

#### H1 — The whole `HouseholdSnapshot` is one `@Observable` property, so every speaker event re-renders the entire panel

**`SonosRemote/App/AppState.swift:12`** — `private(set) var snapshot = HouseholdSnapshot()`

**Mechanism.** The `@Observable` macro tracks access at *stored-property* granularity.
Every view that touches `state.snapshot.anything` registers a dependency on the single
`snapshot` property. `AppState.apply` (`AppState.swift:94-95`) assigns the whole struct
on every event, and Observation's generated setter calls `withMutation(keyPath: \.snapshot)`
**unconditionally — there is no equality check**. So a `groupVolume` push for room A
invalidates the Settings screen's connection banner, the favourites list, the status
banner, and everything else that ever read `snapshot`.

Confirmed read sites (grep count of `state.snapshot` / derived per file):

| File | reads | what it actually needs |
|---|---|---|
| `Views/Main/RoomsListView.swift:16,17,20,21,25,31` | 6 | `groups` |
| `Views/Sound/SoundScreen.swift:7,8,10,23,76` | 5 | `players` |
| `Views/Main/MainScreen.swift:10,11,12,14,15,18` | 5 | one group |
| `Views/Shell/HeaderView.swift:9,22,23,30` | 4 | `screen`, one group |
| `Views/Settings/SettingsScreen.swift:91,96,107,109` | 4 | `status`, `players.count`, `softwareVersion` |
| `Views/Group/GroupScreen.swift:8,14,33,55` | 4 | `players`, `groups` |
| `Views/Favorites/FavoritesScreen.swift:7,8,9,42` | 4 | `favorites` |
| `Views/StatusBannerView.swift:8` | 1 | `status` only — changes ~never |

`StatusBannerView` is the clearest waste: it renders from `snapshot.status`, a value that
changes perhaps five times in a day, and it is embedded in four of the five screens
(`MainScreen.swift:9`, `FavoritesScreen.swift:15`, `GroupScreen.swift:13`,
`SoundScreen.swift:18`). It re-evaluates on every playback tick from every speaker.

**Cost.** Per event: one full body pass over the visible screen (~20-40 view bodies for
MainScreen) plus SwiftUI's diff and a layout pass. Steady-state that is cheap — a playing
group emits maybe 2-4 events per track, so ~40 events/hour. The cost lands during bursts:
a 3-second volume drag over a 3-speaker group produces ~30 outbound POSTs and, by my
reading, ~120 inbound volume events (see H2), each one a full-panel re-render — roughly
**40 full-tree re-renders per second** against a target of 1-2.

**Fix.** Stop storing one opaque blob. Replace the single property with narrow ones and
assign each only when it differs:

```swift
private(set) var status: HouseholdStatus = .discovering
private(set) var groups: [Group] = []
private(set) var players: [Player] = []
private(set) var favorites: [Favorite] = []
private(set) var softwareVersion: String?

func apply(_ new: HouseholdSnapshot) {
    if new.status != status { status = new.status }
    if new.groups != groups { groups = new.groups }
    if new.players != players { players = new.players }
    if new.favorites != favorites { favorites = new.favorites }
    if new.softwareVersion != softwareVersion { softwareVersion = new.softwareVersion }
    ...
}
```

Every model type already conforms to `Hashable` (`Models.swift:15,29,49,71,86,108`), so the
comparisons are cheap relative to a render. This alone takes `StatusBannerView`,
`SettingsScreen`, and `FavoritesScreen` out of the volume-event path entirely.

**Measure.** Instruments → **SwiftUI** template, *View Body* and *View Properties* tracks.
Open the panel, drag a room's volume for three seconds, count `body` invocations per view
type. Re-run after the change; `StatusBannerView` should drop to ~1.

---

#### H2 — `playerVolume:1` events mutate the observed snapshot for data no view renders

**`Packages/SonosKit/Sources/SonosKit/Household/SubscriptionPlan.swift:11`**
`plan[player.id] = [Subscription(namespace: "playerVolume:1", scope: .player(player.id))]`
**`Packages/SonosKit/Sources/SonosKit/Reducer/SnapshotReducer.swift:50`**
`next.playerVolumes[playerID] = volume`
**`Packages/SonosKit/Sources/SonosKit/Models/HouseholdSnapshot.swift:16`**
`public var playerVolumes: [String: Volume]`

**Mechanism.** Every player is subscribed to its own volume namespace, unconditionally, for
the life of the app. Each `playerVolume` push runs the full chain — JSON decode on the
`PlayerSocket` actor, hop to the `Household` actor, reduce, yield, hop to `MainActor`,
assign `snapshot` — and because of H1 that assignment invalidates every view in the panel.
**MEASURED:** `snapshot.playerVolumes` is read by exactly two things, `sonosctl`
(`Sonosctl.swift:69`) and the tests. The app never renders it. `VolumeSliderView` is only
ever constructed with `group.volume` (`VolumeRowView.swift:10`, `RoomRowView.swift:39`).

This is what makes the volume-drag path quadratic in room size: setting *group* volume on a
3-speaker group makes the speakers push 1 `groupVolume` **plus 3 `playerVolume` events**,
so 3 of every 4 re-renders are for data that is never drawn.

**Cost.** ~75% of inbound volume traffic during a drag, plus a JSON decode and two actor
hops each. At 10 sends/s on a 3-speaker group: ~30 wasted decode-reduce-render cycles per
second. Idle cost is zero (no events when nobody touches a volume), so this is purely an
interaction-latency finding, not an energy one.

**Fix.** Cheapest: drop the subscription — delete `SubscriptionPlan.swift:10-12` and the
`playerVolumes` field, and let per-player volume come back if a per-speaker UI is ever
built. If you want to keep the model complete for `sonosctl`, keep the field but move it
out of the observed surface (it is not one of the properties promoted in H1's fix), so
reducing it never triggers a SwiftUI invalidation.

**Measure.** `log stream --process SonosRemote --level info` while dragging, or add a
temporary counter in `Household.handle(socketOutput:)` (`Household.swift:377`) binned per
event case, to confirm the 3:1 ratio on the owner's system.

---

#### H3 — The snapshot stream is unbounded and `Household.apply` yields even when nothing changed

**`Packages/SonosKit/Sources/SonosKit/Household/Household.swift:66-75`** (`snapshots()`)
**`Packages/SonosKit/Sources/SonosKit/Household/Household.swift:418-428`** (`apply`)

**Mechanism.** **MEASURED:** all three `AsyncStream.makeStream()` calls in SonosKit use the
default buffering policy, which is `.unbounded`. For the snapshot stream that is exactly
wrong: a `HouseholdSnapshot` is a *complete state*, not a delta, so an intermediate value
that the `MainActor` has not consumed yet carries no information the next one lacks. When
the producer outruns the consumer, the consumer is forced to render every intermediate
state instead of skipping to the newest.

Compounding it, `apply` (line 418-428) yields to every observer on every event with no
comparison against the previous snapshot. A `playbackStatus` push that reports an unchanged
state, or a `groups` push whose topology is identical (these arrive on every socket
reconnect), still produces a full re-render.

**Cost.** Turns any burst into an unbounded render queue. During the drag scenario above,
40 queued snapshots → 40 renders instead of the ~5 the display can actually show at the
consumer's pace. Memory per queued snapshot is small (COW arrays share storage, ~100 bytes
of struct plus refcount traffic), so this is a CPU/latency finding, not a leak.

**Fix.** Two lines, both safe:

```swift
// Household.swift:67 — dropping intermediates is correct for whole-state values
let (stream, continuation) = AsyncStream<HouseholdSnapshot>.makeStream(
    bufferingPolicy: .bufferingNewest(1))

// Household.swift:419 — skip no-op events entirely
let next = SnapshotReducer.reduce(snapshot, event)
guard next != snapshot else { return }
```

`HouseholdSnapshot: Hashable` (`HouseholdSnapshot.swift:11`) so the guard compiles as-is.
Note `PlaybackProgress.reportedAt` (`Models.swift:52`) changes on every `playbackStatus`
push, so those will not dedupe — volume echoes, metadata repeats and identical topology
pushes will.

**Do not** apply `.bufferingNewest` to `PlayerSocket.outputs` (`PlayerSocket.swift:38`) or
the discovery stream (`BonjourDiscovery.swift:34`) — those carry deltas and dropping one
loses state.

**Measure.** Instruments → **Time Profiler**, or a counter comparing
`SnapshotReducer.reduce` calls against distinct snapshots yielded, over a minute of normal
playback.

---

#### H4 — The favourites list is an eager `VStack`: every row, and every row's artwork download, materialises on open

**`SonosRemote/Views/Favorites/FavoritesScreen.swift:34-40`**
**`SonosRemote/Views/Components/Card.swift:8`** — `VStack(spacing: 0) { content() }`
**`SonosRemote/Views/Favorites/FavoriteRow.swift:12`** — `Artwork(url: favorite.imageURL, size: 40, ...)`

**Mechanism.** **MEASURED:** there is no `LazyVStack`, `LazyHStack` or `List` anywhere in
the app. `Card` wraps its content in a plain `VStack`, and `FavoritesScreen` puts a
`ForEach` over *all* filtered favourites inside it, inside the shell's `ScrollView`
(`PanelShellView.swift:17`). A plain `VStack` builds and lays out every child immediately,
regardless of the 640 pt viewport clamp at `PanelShellView.swift:22`. Each child contains
an `Artwork` → `AsyncImage` (`Artwork.swift:10`), and `AsyncImage` starts its fetch as soon
as it appears.

**Cost.** With ~100 favourites, opening the Favorites screen builds 100 rows, 100
`AsyncImage` instances, and kicks off **100 artwork HTTP requests** — to Sonos and to
streaming-service CDNs — of which perhaps 8 are on screen. Paid again on every open,
because the panel's view tree is torn down on dismiss (`PanelShellView.swift:33`
`.onDisappear` confirms the views do disappear). At 30-80 KB per image that is 3-8 MB of
network per open, plus the decode cost in M3.

**Fix.** Make the favourites list lazy. Add a lazy variant of `Card` rather than changing
the existing one (the other three `Card` call sites are short and should stay eager):

```swift
struct LazyCard<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        LazyVStack(spacing: 0) { content() }
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.horizontal, 16)
    }
}
```

`LazyVStack` only materialises children near the visible region, so the 100 downloads
become ~8. Pair it with the artwork cache in M3 so re-opens cost nothing.

**Measure.** `nettop -p <pid> -l 1` before and after opening the Favorites screen for byte
counts and connection count; Instruments → **Network** template for the request fan-out;
SwiftUI template's *View Body* track for the row count built.

---

#### H5 — Every playback subscription stays live while the panel is closed, all day

**`Packages/SonosKit/Sources/SonosKit/Household/SubscriptionPlan.swift:5-6`**
```swift
static let householdNamespaces = ["groups:1", "favorites:1"]
static let groupNamespaces = ["playback:1", "playbackMetadata:1", "groupVolume:1"]
```
**`Packages/SonosKit/Sources/SonosKit/Household/Household.swift:370-375`** (`reconcileSubscriptions`)
**`SonosRemote/App/AppState.swift:135-138`** (`setPanelPresented` — the only panel-state hook)

**Mechanism.** Subscriptions are computed purely from topology and never from whether
anyone is looking. `setPanelPresented` does exactly one thing: start or stop the 1 Hz tick
(`updateTicking`, `AppState.swift:140-154`). Meanwhile every playing group keeps pushing
`playbackStatus` and `playbackMetadata` into a panel that is not on screen, and each push
runs the full chain: `JSONDecoder` allocation and decode in `SocketFrameDecoder.decode`
(`SocketFrame.swift:83` — a fresh decoder per frame), hop to the `Household` actor, reduce,
yield, hop to `MainActor`, mutate `snapshot`.

This is the single biggest idle-energy item for an app whose normal state is "closed, in
the menu bar, while music plays for eight hours".

**Cost.** Inferred: with music playing all day, ~2-4 events per track × ~15 tracks/hour ×
8 hours ≈ **500-1000 wake-decode-reduce-hop cycles per day that nothing renders**, plus
whatever volume changes the household makes from phones and the Sonos app. Each cycle is
small (tens of microseconds of CPU) but each is a process wake, which is what macOS's
energy accounting punishes and what keeps the CPU out of deeper idle states.

**Fix.** The machinery already exists — `PlayerSocket.setSubscriptions`
(`PlayerSocket.swift:56-60`) computes an un/subscribe diff and is already called on every
topology change. Add a "panel is open" input to the plan:

1. Give `Household` an `setPanelVisible(_:)` that stores the flag and calls
   `reconcileSubscriptions()`.
2. In `SubscriptionPlan.make`, take the flag and emit `groupNamespaces` only when visible;
   always keep `groups:1` and `favorites:1` so topology stays correct.
3. On open, after re-subscribing, call `refreshTopology()` once so the first paint is
   current (the speakers push current state on subscribe anyway).
4. Wire it from `AppState.setPanelPresented` alongside `updateTicking()`.

Keep the sockets themselves open — reconnecting N websockets on every panel open would cost
more than it saves (N TLS handshakes, ~50 ms each) and would make the panel feel slow.

**Measure.** `sudo powermetrics --samplers tasks -n 5 | grep -i sonos` with the panel
closed and music playing, before and after — watch the *idle wakeups* and *energy impact*
columns. Activity Monitor's Energy tab shows the same numbers less precisely. Confirm the
event rate with `log stream --process SonosRemote --level info`.

---

### MEDIUM

#### M1 — `orderedGroups` re-sorts with ICU collation on every single access

**`SonosRemote/App/AppState.swift:15-22`**

A computed property that runs `sorted` with `localizedStandardCompare` on every read.
`RoomsListView` reads it twice — once in `body` at line 20, once inside `onMoveCommand` at
line 25 on every arrow-key press — and `FavoritesScreen.targetOptions` (line 8) reads it a
third time. Each access allocates a fresh `[Group]` (each `Group` carries a `String` name,
a `String` coordinatorID, a `[String]`, and an optional `NowPlaying` with six more optional
`String`/`URL` fields, so ~40 retain/release pairs for 8 groups) and runs ~24 ICU
collation comparisons at roughly 1-3 µs each.

**Cost.** ~30-80 µs per access; 2-3 accesses per render. Negligible at 1 render/s, ~5 ms/s
of pure waste at H1's burst rate. The allocation churn matters more than the CPU.

**Fix.** Store it. Add `private(set) var orderedGroups: [Group] = []` and recompute once in
`apply()` (`AppState.swift:94`) and `select()` — one sort per *event* instead of one per
*render*. This also composes with H1: `orderedGroups` becomes its own observable property,
so views depending on room ordering stop depending on the whole snapshot.

**Measure.** Time Profiler, filter for `localizedStandardCompare` and
`Array.sorted(by:)`, during a volume drag.

#### M2 — `FavoritesFilter.apply` runs four times per FavoritesScreen render, allocating a lowercased copy of every string

**`SonosRemote/App/FavoritesFilter.swift:5-12`**, called via
**`SonosRemote/Views/Favorites/FavoritesScreen.swift:7`** and read at lines **22, 25, 27, 35**.

`filtered` is a computed property, so each of those four reads re-runs the whole filter.
The filter itself calls `.lowercased()` on the query once but on **three fields of every
favourite, on every call** (line 9-10) — all fresh heap allocations.

**Cost.** 100 favourites × 3 fields × 4 reads = **1,200 String allocations per render**.
The screen re-renders on every keystroke *and* (because of H1) on every unrelated speaker
event while it is open.

**Fix.** Two changes. In the view, bind once: `let filtered = filtered` at the top of `body`
and use the local. In the filter, stop allocating — use
`favorite.name.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil`,
or precompute a lowercased search key on `Favorite` once when favourites are assigned.

#### M3 — `AsyncImage` decodes artwork at full resolution for 22 pt and 40 pt thumbnails, with no cache

**`SonosRemote/Views/Artwork.swift:10`** — `AsyncImage(url: url)`, then `.frame(width: size, height: size)` at line 20.

Call sites: `HeroView.swift:15` (96 pt), `RoomRowView.swift:18` (40 pt × N groups),
`FavoriteRow.swift:12` (40 pt × N favourites), `GroupScreen.swift:16` (40 pt),
`HeaderView.swift:22` (22 pt).

**Mechanism.** `AsyncImage` downloads the full asset and decodes it at native resolution;
the `.frame` only scales the already-decoded bitmap. Album art from streaming services is
commonly 640² or 1280². It also holds its image in `@State`, so the image survives body
re-evaluations of the *same* view identity but is lost whenever the view is torn down —
which is every panel dismiss (`PanelShellView.swift:33`). Any caching comes only from
`URLSession.shared`'s `URLCache`, which depends on the artwork server's headers; Sonos's
own `/getaa` endpoint and many service CDNs send no-store.

Separately, `HeaderView.swift:22` and `HeroView.swift:15` render **the same URL** at
different sizes as two independent view identities — two downloads, two decodes.

**Cost.** A 1280² RGBA decode is ~6.5 MB of bitmap. Ten visible 40 pt rows at that source
size ≈ 65 MB of image memory for ~64 KB of actual pixels — a ~100× overdraw on decode and
resident memory. Plus a re-download on every panel open.

**Fix.** Replace `AsyncImage` with a small loader:

- One `actor ArtworkCache` holding an `NSCache<NSURL, NSImage>` keyed by URL *and* target
  pixel size, shared app-wide so the header and hero share a hit.
- Decode with `CGImageSourceCreateThumbnailAtIndex` and
  `kCGImageSourceThumbnailMaxPixelSize = size * backingScaleFactor`, plus
  `kCGImageSourceCreateThumbnailFromImageAlways`. This decodes straight to thumbnail size
  instead of decoding full then scaling.
- Keep the existing SF Symbol placeholder branch (`Artwork.swift:14-17`) for the miss path.

**Measure.** Instruments → **Allocations** plus the VM Tracker, filtering for `ImageIO` and
`CGImage`; watch resident bitmap memory when opening the Favorites screen.

#### M4 — Every EQ change sends four SOAP writes; every EQ read does four serial round trips

**`Packages/SonosKit/Sources/SonosKit/UPnP/UPnPClient.swift:69-76`** (`apply`)
**`Packages/SonosKit/Sources/SonosKit/UPnP/UPnPClient.swift:61-67`** (`eqSettings`)

`apply` unconditionally issues `SetBass`, `SetTreble`, `SetLoudness` and (if present)
`SetEQ SubGain` — four HTTP POSTs — even when the user only toggled loudness
(`SoundScreen.swift:57-60`) or moved one slider (`SoundScreen.swift:33-47`). `eqSettings`
does the mirror image on read: four `await`s in sequence, each a separate round trip.

**Cost.** Writes: 4 requests where 1 suffices; a user tapping through three presets
(`PresetChips.swift:10-17`) fires 12 POSTs. Reads: at ~100 ms per LAN round trip, the
Sound screen takes ~400 ms to populate instead of ~100 ms.

**Fix.** For reads, run them concurrently — they are independent:

```swift
async let bass = bass(address: address)
async let treble = treble(address: address)
async let loudness = loudness(address: address)
async let sub = hasSub ? eq(type: "SubGain", address: address) : nil
return try await EQSettings(bass: bass, treble: treble, loudness: loudness, subGain: sub)
```

For writes, diff against the previous value — `AppState.eqByPlayer` (`AppState.swift:35`)
already holds it — and send only the fields that changed. `EQSettings: Hashable`
(`Models.swift:139`) so the comparison is free.

#### M5 — `SMAppService.mainApp.status` is queried on every SettingsScreen body evaluation

**`SonosRemote/Views/Settings/SettingsScreen.swift:8`**
`@State private var launchAtLogin = SMAppService.mainApp.status == .enabled`

**Mechanism.** A `@State` default expression is evaluated every time the view struct is
initialised, even though SwiftUI only *uses* the value on first appearance. `SettingsScreen`
reads `state.snapshot` at lines 91, 96, 107 and 109, so under H1 it is re-initialised on
every speaker event while it is open. `SMAppService.status` is not a cheap property read —
it consults the login-items database. The `onChange` handler at lines 79 and 85 queries it
twice more per toggle.

**Cost.** One login-items query per speaker event while the Settings screen is open.
Unmeasured, but this class of call is typically hundreds of microseconds to milliseconds
and can block the main thread.

**Fix.** Default to `false` and load in `.onAppear`:

```swift
@State private var launchAtLogin = false
...
.onAppear { launchAtLogin = SMAppService.mainApp.status == .enabled }
```

**Measure.** Time Profiler with the Settings screen open and a room playing; look for
`SMAppService` / `LaunchServices` frames on the main thread.

#### M6 — The bootstrap loop re-fetches topology *and* favourites every ≤60 s forever if favourites never succeed

**`Packages/SonosKit/Sources/SonosKit/Household/Household.swift:207-235`**

The loop calls `await self.refreshTopology()` at the top of **every** iteration (line 214)
and only returns once `favoritesLoaded` is true (lines 222-225). If the favourites fetch
fails permanently — a household with no music services, a 4xx from `/households/local/favorites`
— the loop never exits. Backoff caps at 60 s (`Backoff.swift:9`), so it settles into a
steady **two HTTPS requests every 60 seconds, forever, with the panel closed**.

Worse, each `refreshTopology()` also runs `ensureSockets()`, `reconcileSubscriptions()` and
`probeSubs()` (`Household.swift:301-303`), so a full subscription reconcile across every
socket happens every 60 s too.

**Cost.** ~2,880 HTTPS requests/day plus 1,440 subscription reconciles, each waking the
process, in a failure mode the user would never see. Zero cost in the happy path, where the
loop exits after two requests.

**Fix.** Two changes: (a) don't re-fetch topology once status is `.ready` — hoist the
`refreshTopology()` call so it only runs while the status is not yet ready; (b) cap the
favourites retries (five attempts, say) and then give up, relying on the `favoritesChanged`
socket event (`Household.swift:409-410`) and the next panel open to fill them in.

**Measure.** `log stream --process SonosRemote --predicate 'category == "household"'` for
one minute — a repeating "fetching topology from …" line every 60 s is the signature.

#### M7 — `URLSessionTransport` is never invalidated, so every `retryDiscovery()` leaks a `URLSession` and overlaps two live households

**`SonosRemote/App/AppState.swift:80-92`** (`retryDiscovery`)
**`Packages/SonosKit/Sources/SonosKit/Transport/URLSessionTransport.swift:10-16`**

`URLSession(configuration:delegate:delegateQueue:)` retains its delegate — and itself —
until `invalidateAndCancel()` or `finishTasksAndInvalidate()` is called. `URLSessionTransport`
has no `deinit` and never invalidates. `retryDiscovery` builds a brand-new
`URLSessionTransport` on line 87 and simply drops the old one; the old session, its
`TrustDelegate`, and its connection pool live until the process exits.

Separately, line 85 tears the old household down with a fire-and-forget
`Task { await old.stop() }` while line 87-91 immediately starts a new one. There is a
window where **both** households hold sockets to every player — double the websockets,
double the pings — until the detached stop actually runs. The same fire-and-forget pattern
appears inside `Household.stop()` itself (`Household.swift:96-99`).

**Cost.** Per retry: one leaked `URLSession` + delegate + pool (a few KB and some kernel
socket state), and a brief 2× socket count. The retry button lives in two places
(`SettingsScreen.swift:27`, `StatusBannerView.swift:27`), and a user fighting a flaky
network may press it many times.

**Fix.** Give `URLSessionTransport` a `deinit { session.invalidateAndCancel() }`, or
better an explicit `close()` that `Household.stop()` calls. In `retryDiscovery`, await the
old household's stop before constructing the new one — make it `async`, or chain it:
`Task { await old.stop(); await MainActor.run { self.startFresh() } }`.

**Measure.** Instruments → **Leaks** / Allocations, generation-marked around five presses of
the Settings refresh button; watch the `__NSURLSessionLocal` and `NSURLSessionTask` counts.
`nettop -p <pid>` will also show the doubled connection count during the overlap.

#### M8 — 30-second websocket ping on every player, forever

**`Packages/SonosKit/Sources/SonosKit/Socket/PlayerSocket.swift:13`**
`static let pingInterval: Duration = .seconds(30)`, driven by the pinger task at lines 107-113.

Each player's socket wakes every 30 s to send a WebSocket ping. Five players = 10 wakeups
per minute = **~14,400 process wakeups per day** that do nothing but prove the socket is
alive. Each is cheap in CPU (a small TCP write, maybe 100 µs) — ~1.5 s of CPU per day — but
wakeups are exactly what prevents sustained low-power idle on a laptop.

The pings are naturally staggered (each starts when its socket connects), which is good and
should be preserved.

**Fix.** Raise to 60-120 s. The purpose is dead-peer detection, and the reconnect path
(`PlayerSocket.swift:119-128`) already handles a drop within one backoff cycle; a 2-minute
detection latency on a LAN device is fine, especially if you add the path monitor in M11,
which detects the real failure case (network change) instantly. Consider skipping pings
entirely while the panel is closed and the app is not subscribed to playback (H5) — a stale
socket then costs nothing until the next open, which can force a reconnect.

**Measure.** `sudo powermetrics --samplers tasks -n 5 | grep -i sonos`, idle wakeups column,
with the panel closed and nothing playing. That isolates the pings from event traffic.

#### M9 — `String(describing: error)` is built eagerly on every failed request, before the logger can discard it

**`Packages/SonosKit/Sources/SonosKit/Transport/URLSessionTransport.swift:30`**
**`Packages/SonosKit/Sources/SonosKit/Household/Household.swift:305, 310, 324`**

```swift
logger.error("request to \(request.url.absoluteString, privacy: .public) failed: \(String(describing: error), privacy: .public)")
```

`os.Logger`'s string interpolation defers *formatting*, not *argument evaluation*.
`String(describing: error)` and `request.url.absoluteString` are ordinary function calls
evaluated at the call site, so both strings are allocated whether or not the log level is
enabled or the message is ever read. `String(describing:)` on an `NSError`-backed `URLError`
goes through reflection and is not cheap.

**Cost.** Negligible when the network is healthy (these are error paths). During an outage
with a slider drag at 10 commands/s, ~10 reflective descriptions per second plus the URL
string — a self-inflicted cost precisely when the app is already struggling.

**Fix.** Guard the hot one, or use the cheaper interpolations `os.Logger` handles natively:

```swift
if logger.logLevel <= .error {  // or just drop the describing() for the error case
    logger.error("request to \(request.url.absoluteString, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
}
```

`URLError` is `CustomStringConvertible`-cheap via `localizedDescription`; better still, log
only `(error as? URLError)?.code.rawValue` in the hot path.

The rest of the logging is well placed — see "Already efficient".

#### M10 — The volume slider allocates and cancels a `Task` on every 1-unit step, and permits 10 POSTs/s

**`SonosRemote/Views/VolumeSliderView.swift:39-47`** (`onChange(of: local)`)
**`SonosRemote/Views/VolumeSliderView.swift:91-98`** (`scheduleFlush`)
**`SonosRemote/App/VolumeCommandGate.swift:11`** — `minimumInterval: TimeInterval = 0.1`

`Slider(value:in:step:1)` fires `onChange` on every 1-unit crossing, so a full-range drag
produces ~100 callbacks. Each one that the gate defers calls `scheduleFlush()`, which
**cancels the previous task and allocates a new one** — up to ~90 `Task` creations and
cancellations per drag, each with a `Task.sleep` registration on the concurrency runtime.

Separately, `minimumInterval: 0.1` allows 10 HTTPS POSTs per second, each producing the
echo storm described in H2.

**Cost.** ~90 task allocations per drag (small, but pure churn on the main actor), and
~30 POSTs per 3-second drag.

**Fix.** In `scheduleFlush`, return early if a flush is already scheduled and unfired —
the gate's own `hasPending` (`VolumeCommandGate.swift:16`) already tracks the state, so one
long-lived flush task can re-check rather than being rebuilt per step. Raise
`minimumInterval` to 0.15-0.2 s; a Sonos speaker cannot meaningfully act on 10 volume
changes per second anyway, and the slider's local value already gives immediate visual
feedback.

#### M11 — No network-path or wake monitoring: up to 60 s dead after sleep or a Wi-Fi change, and the reconnect jitter is positive-only

**`Packages/SonosKit/Sources/SonosKit/Socket/PlayerSocket.swift:127`**
**`Packages/SonosKit/Sources/SonosKit/Socket/Backoff.swift:9,16-22`**

Two related problems.

*Latency.* Nothing observes `NWPathMonitor` or `NSWorkspace.didWakeNotification`. After a
lid close, a Wi-Fi switch, or a VPN toggle, every socket fails, backoff climbs to its 60 s
cap, and the app can sit disconnected for a full minute after the network is fine again. For
a menu-bar app whose whole value is "click, it works", that is the worst possible failure.

*Synchronisation.* `Backoff.delay` (lines 16-22) applies jitter as `capped + capped * j`
where `j ∈ [0, 0.25]` — jitter is **additive-only**, so the delay is in `[d, 1.25d]` and no
socket ever retries *earlier* than the base. When N players fail simultaneously (which is
the normal case: the failure is the Mac's network, not the speakers'), all N attempt
counters advance in lockstep and all N reconnect within the same 25% window — N
simultaneous TLS handshakes with self-signed certs, repeatedly.

**Cost.** Up to 60 s of apparent deadness per network transition; N-way handshake bursts
during flaps.

**Fix.** Add an `NWPathMonitor` in `Household`; on `.satisfied`, reset every socket's
attempt counter and nudge an immediate reconnect (a `PlayerSocket.reconnectNow()` that
cancels the sleep). Subscribe to `NSWorkspace.shared.notificationCenter`'s
`didWakeNotification` for the same. Change the jitter to full decorrelation —
`random ∈ [0, 1]` scaling the whole delay (`capped * (0.5 + 0.5 * random)`) so retries
spread across a real window.

---

### LOW

#### L1 — The panel renders at zero height for one frame on every open
**`SonosRemote/Views/Shell/PanelShellView.swift:10,20,22`** — `bodyHeight` starts at `0`, and
the ScrollView's frame is `min(bodyHeight, 640)`. The first layout pass gives height 0;
`onGeometryChange` then fires and snaps to the real height. A visible jump on every open.
**Fix:** seed `bodyHeight` with a typical value (e.g. `420`) so the first frame is close.

#### L2 — Three dictionaries/sets grow without bound
`AppState.errorGeneration` (`AppState.swift:50`) gains an entry per group id that ever errored
and is never pruned — `report` (line 234) clears `rowErrors` but not `errorGeneration`.
`Household.addresses` (`Household.swift:34`) and `removedPlayers` (line 44) likewise only grow
(`removedPlayers` shrinks only on re-`.found`). All are a few hundred bytes over a day, so
this is hygiene, not a leak. **Fix:** clear the `errorGeneration` entry in the same branch
that clears `rowErrors`; prune `addresses` on `.lost`.

#### L3 — `ForEach(Array(…enumerated()))` allocates a tuple array and weakens diffing
**`FavoritesScreen.swift:35`**, **`GroupScreen.swift:29`**. The `enumerated()` exists only to
compute `isFirst`. It allocates a fresh `[(Int, Element)]` per render and makes every row's
value change when the list order shifts, so SwiftUI cannot skip unchanged rows.
**Fix:** `ForEach(filtered) { fav in CardRow(isFirst: fav.id == filtered.first?.id) { … } }`,
or draw the separator as an overlay and drop `isFirst` entirely.

#### L4 — `RoomRowView`'s `FocusState.Binding` may defeat SwiftUI's "skip unchanged row" optimisation
**`SonosRemote/Views/Main/RoomRowView.swift:9`** — `let focus: FocusState<String?>.Binding`.
SwiftUI decides whether to re-invoke `body` by comparing the view's stored properties; a
`Binding` is not meaningfully comparable, so every row may re-render whenever the parent
does, even when its `group` value is identical. **Inferred, needs confirming** — measure
`RoomRowView.body` invocations in the SwiftUI instrument while changing one room's volume;
if all N rows re-render, hoist focus handling into the parent (pass a plain `Bool
isFocused` down and let `RoomsListView` own the `@FocusState`).

#### L5 — Groups are sorted twice per topology event
`SnapshotReducer.reduce` sorts groups and players by `localizedStandardCompare`
(`SnapshotReducer.swift:26,29`); `AppState.orderedGroups` (`AppState.swift:16-21`) then sorts
groups again by a different key (active-first, then name). The reducer's group sort is
thrown away by the view layer. **Fix:** drop the group sort in the reducer (keep the player
sort — `GroupScreen` and `SoundScreen` rely on name order), or move the active-first rule
into the reducer and delete `orderedGroups` (see M1).

#### L6 — Snapshot lookups are linear scans; `MembershipRow` is O(groups × players)
`HouseholdSnapshot.group(_:)`, `player(_:)` and `group(containing:)`
(`HouseholdSnapshot.swift:28-30`) are `first { }` scans. `MembershipRow`
(`GroupScreen.swift:55`) calls `group(containing:)` once per row, so rendering the Group
screen is O(players × groups). At realistic sizes (≤10 each) this is ~100 pointer compares —
irrelevant today, worth knowing if the app ever targets a 30-speaker household.

#### L7 — `MainScreen` evaluates `state.selectedGroup` three times per body
**`SonosRemote/Views/Main/MainScreen.swift:10,11,14,15`** — three linear group scans and three
redundant optional unwraps where one `let group = state.selectedGroup` at the top would do.
Clarity as much as speed.

#### L8 — One `Task` allocated per incoming volume event per visible slider
**`SonosRemote/Views/VolumeSliderView.swift:77-81`** — `setLocalProgrammatically` spawns
`Task { @MainActor in isProgrammaticUpdate = false }` to release the guard flag on the next
run-loop turn. With N sliders visible in the rooms list and a group-volume event arriving,
that is N task allocations per event. Correct, just churny. **Fix:** if a synchronous
release is possible (the `onChange` fires within the same transaction), drop the Task;
otherwise this is acceptable as-is.

#### L9 — `probeSubs` serialises a UPnP round trip per player
**`Packages/SonosKit/Sources/SonosKit/Household/Household.swift:331-340`** — a `for` loop with
`await upnp.hasSub(address:)` inside, one player at a time. With 10 players and an 8 s
request timeout (`URLSessionTransport.swift:13`), a bad network serialises up to 80 s of
probing. The actor stays responsive (each `await` is a reentrancy point) and the
`subProbed`/`subProbeInFlight` guards (lines 35, 38) correctly prevent duplicates, so this is
latency only. **Fix:** a `withTaskGroup` over the unprobed players.

#### L10 — `PlayerSocket` holds a retain cycle broken only by `stop()`
**`Packages/SonosKit/Sources/SonosKit/Socket/PlayerSocket.swift:43`** — `runTask = Task { await run() }`
captures `self` strongly and is stored on `self`. Every current path does call `stop()`
(`Household.stopSocket` line 362-368 and `Household.stop` line 96-99), so there is no leak
today — but one missed path yields an immortal actor running a reconnect loop forever.
**Fix:** `Task { [weak self] in await self?.run() }`, matching the `[weak self]` discipline
used everywhere else in `Household`.

---

## Already efficient — do not "fix" these

Worth recording, because several of them look like problems and are not.

- **The tick is correctly scoped.** `AppState.updateTicking` (`AppState.swift:140-154`) runs
  the 1 Hz task only when `panelPresented && selectedGroup?.playbackState == .playing`, and
  `PanelShellView` drives it from two directions (`onChange` at line 29 and a belt-and-braces
  `onDisappear` at line 33). **Nothing ticks while the panel is closed.**
- **Only `ProgressBarView` re-renders on the tick.** `ProgressBarView.swift:11` is the sole
  reader of `state.tick`; grep confirms no other view touches it. Observation's per-property
  tracking means the once-a-second invalidation is confined to that one view body.
- **`PanelShellView`'s `onGeometryChange` does *not* fire on each tick.**
  (`PanelShellView.swift:20`) The action only runs when the measured value *changes*, and the
  progress bar's height is constant across ticks (fixed 3 pt capsule plus a
  `monospacedDigit` caption whose height never varies). The transform closure runs per layout;
  `bodyHeight` is not reassigned, so the shell does not re-render. It will fire correctly on
  the real triggers — screen switches, an `ErrorLine` appearing, a status banner.
- **The geometry loop is correctly structured.** The measured subtree has a fixed
  `.frame(width: 420)` (`PanelShellView.swift:19`) and its height does not depend on the
  ScrollView frame it feeds, so the classic `onGeometryChange` → `frame(height:)` oscillation
  cannot occur here.
- **One `URLSession` for everything.** `URLSessionTransport` (`URLSessionTransport.swift:15`)
  is shared by the REST client, the UPnP client and every websocket — one connection pool,
  one TLS session cache, one trust delegate. This is the right call and avoids the
  per-client-session anti-pattern.
- **No `Connection: Close`, so keep-alive works.** **MEASURED** — repeated POSTs to a
  coordinator reuse the TLS connection; the custom `TrustDelegate`
  (`URLSessionTransport.swift:57-69`) runs only on new handshakes, not per request.
- **Decoding and reducing never touch the main actor.** `SocketFrameDecoder.decode` runs on
  the `PlayerSocket` actor (`PlayerSocket.swift:115`), `SnapshotReducer.reduce` on the
  `Household` actor (`Household.swift:420`). Only the final `AppState.apply` is main-actor
  work. This is exactly right and is the reason H1's cost is bounded.
- **`SnapshotReducer` is pure.** (`SnapshotReducer.swift:4`) No I/O, no allocation beyond the
  new snapshot, fully unit-tested — cheap to call and cheap to reason about.
- **Weak-self discipline in `Household`.** `start` (line 81), `startBootstrap` (line 209),
  `armDiscoveryTimeout` (line 242), `ensureSockets`' consumer task (line 352) and the stream's
  `onTermination` (line 71) all use `[weak self]`. No retain cycles in the actor.
- **Exponential backoff with a cap, and the attempt counter resets on success.**
  (`PlayerSocket.swift:105,127-128`; `Backoff.swift:16-22`) The shape is right; only the
  jitter formula needs work (M11).
- **`subProbed` / `subProbeInFlight` de-duplication.** (`Household.swift:35-38,331-340`)
  Probes run once per player per session, and a *failed* probe deliberately does not mark the
  player probed (line 336-337) so `hasSub` is retried rather than pinned false. Careful work.
- **No logging in the per-event hot path.** `Household.apply` logs only on a *status change*
  (`Household.swift:422-424`), not per snapshot. Socket connect/disconnect logging
  (lines 381, 384) is per-connection, not per-message.
- **The volume gate's incoming suppression is correct.** `VolumeCommandGate.shouldAcceptIncoming`
  (`VolumeCommandGate.swift:38-41`) plus the `isProgrammaticUpdate` guard
  (`VolumeSliderView.swift:45,77-81`) genuinely prevents the echo-loop bug. It does not
  prevent re-renders (that is H1/H2), but the thumb behaviour is right.
- **`ToneSlider` only commits on editing-end.** (`ToneSlider.swift:15-17`) No request storm
  from EQ dragging — contrast with the volume slider, which deliberately streams.
- **Startup does almost nothing.** `SonosRemoteApp.init` (`SonosRemoteApp.swift:11-20`)
  constructs two objects, starts one `Task`, and registers a shortcut handler. No blocking
  I/O, no disk reads beyond a single `UserDefaults.string` (`AppState.swift:58`). Discovery
  runs entirely off the init path with a 10 s timeout (`Household.swift:16`).
- **`start()` is idempotent.** (`AppState.swift:70`, `Household.swift:78`) Both guard against
  double-start.
- **`excludingRemovedPlayers` avoids resurrect-then-remove churn.** (`Household.swift:444-453`)
  Filtering raced topology payloads at the source prevents a snapshot flap — and therefore a
  render flap — that would otherwise be visible.

---

## Prioritised top 5

1. **H1 — Split `snapshot` into narrow `@Observable` properties with equality-guarded
   assignment** (`AppState.swift:12,94`). Highest leverage in the codebase: it takes the
   status banner, settings, favourites and sound screens out of the per-event render path
   entirely. ~20 lines. Do this first; several other findings shrink once it lands.
2. **H3 — `.bufferingNewest(1)` on the snapshot stream plus `guard next != snapshot` in
   `Household.apply`** (`Household.swift:67,419`). Two lines, no behaviour change, and it
   converts every burst from "render every intermediate" to "render the latest". Pairs with
   H1 to fix the volume-drag path completely.
3. **H5 — Drop the playback subscriptions while the panel is closed**
   (`SubscriptionPlan.swift:5-6`, `Household.reconcileSubscriptions`, wired from
   `AppState.setPanelPresented`). The single biggest energy win for an app that is closed
   23 hours a day. The un/subscribe diffing machinery already exists.
4. **H4 + M3 — `LazyVStack` for the favourites list and a thumbnail-decoding artwork cache**
   (`FavoritesScreen.swift:34`, `Card.swift:8`, `Artwork.swift:10`). Turns ~100 downloads and
   ~650 MB of full-resolution decode on a Favorites open into ~8 downloads of correctly-sized
   thumbnails, cached across panel opens.
5. **H2 — Stop subscribing to `playerVolume:1`** (`SubscriptionPlan.swift:11`). A one-line
   deletion that removes ~75% of the inbound event traffic during a volume drag, because
   **MEASURED** nothing in the app renders `playerVolumes`.

Runner-up, worth doing in the same pass because it is cheap and user-visible: **M11's
`NWPathMonitor`** — the up-to-60-second dead window after a lid close is the most likely
thing to make this app feel broken, and no amount of render tuning hides it.
