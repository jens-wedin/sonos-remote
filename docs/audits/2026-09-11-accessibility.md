# Accessibility Audit Results — Remote for Sonos (macOS menu bar app)

**Scan mode:** static / manual source review (the house skill's runtime axe-core and jsx-a11y
tooling is web-only and does not apply to a native SwiftUI target; severity scale and report
structure from `a11y-skill/a11y-qa/SKILL.md` are applied as written)
**Standards:** WCAG 2.2 Level AA + Apple macOS Human Interface Guidelines (Accessibility)
**Date:** 2026-09-11
**Files scanned:** 27 Swift files under `SonosRemote/Views/**` and `SonosRemote/App/**`
(`Packages/SonosKit` is UI-free and out of scope)
**Not performed:** the app was not launched, no VoiceOver session was run, no speaker state was
changed. Contrast figures below are computed from Apple's documented semantic colour alpha values
against the standard light/dark window background and should be confirmed with a colour meter on
the rendered translucent panel material.

---

## Summary

| File | Findings | Worst severity |
|------|----------|----------------|
| `Views/Main/RoomRowView.swift` | 5 | Critical |
| `Views/Main/TransportView.swift` | 5 | Critical |
| `Views/VolumeSliderView.swift` | 4 | Critical |
| `Views/Shell/HeaderView.swift` | 4 | Critical |
| `Views/Main/ProgressBarView.swift` | 2 | Serious |
| `Views/Main/HeroView.swift` | 4 | Serious |
| `Views/Group/GroupScreen.swift` | 2 | Serious |
| `Views/Components/ErrorLine.swift` | 2 | Serious |
| `Views/StatusBannerView.swift` | 3 | Serious |
| `Views/Sound/SoundScreen.swift` | 3 | Serious |
| `Views/Sound/PresetChips.swift` | 3 | Serious |
| `Views/Components/SectionLabel.swift` | 2 | Serious |
| `Views/Shell/FooterView.swift` | 2 | Critical |
| `Views/Components/SearchField.swift` | 3 | Serious |
| `Views/Components/IconButton.swift` | 2 | Critical |
| `Views/Components/RoomPicker.swift` | 1 | Moderate |
| `Views/Shell/PanelShellView.swift` | 2 | Moderate |
| `Views/Main/RoomsListView.swift` | 3 | Critical |
| `Views/Settings/SettingsScreen.swift` | 3 | Serious |
| `Views/Favorites/FavoriteRow.swift` | 2 | Minor |
| `Views/Favorites/FavoritesScreen.swift` | 2 | Serious |
| `Views/Sound/ToneSlider.swift` | 2 | Moderate |
| `App/AppState.swift` | 3 | Serious |

**Total findings:** 29
**Critical: 1 | Serious: 7 | Moderate: 10 | Minor: 11**

Three whole-app absences drive most of the list (confirmed by grep across `SonosRemote/**`):

- zero uses of `AccessibilityNotification` / any announcement API → the 4.1.3 cluster,
- zero uses of `accessibilityHint` → several non-obvious interactions are undiscoverable,
- zero reads of `accessibilityReduceMotion`, `colorSchemeContrast`, `differentiateWithoutColor`
  or `dynamicTypeSize` → the app does not adapt to any of the four macOS accessibility display
  settings.

---

## Critical

### C1. With Full Keyboard Access off (the macOS default), almost nothing in the panel is reachable by keyboard

**WCAG criterion:** 2.1.1 Keyboard (Level A); 2.4.3 Focus Order (Level A)
**Files:**
`Views/Components/IconButton.swift:18`, `Views/Shell/HeaderView.swift:19`,
`Views/Shell/FooterView.swift:9`, `Views/Main/TransportView.swift:40`,
`Views/VolumeSliderView.swift:32,70`, `Views/Favorites/FavoriteRow.swift:27`,
`Views/Sound/PresetChips.swift:14`, `Views/Sound/ToneSlider.swift:15`,
`Views/Settings/SettingsScreen.swift:30,40,64`, `Views/Components/SearchField.swift:17`,
`Views/Main/RoomsListView.swift:15,24`

**What a user experiences:** a keyboard-only user who does not run VoiceOver opens the panel with
the global shortcut. Nothing has focus. Pressing Tab moves nowhere useful — on macOS with
"Keyboard navigation" switched off, Tab only reaches text fields and lists, so the only control
that ever receives focus in the whole app is the Favorites search field
(`SearchField.swift:10`). Play/pause, next/previous, shuffle, repeat, volume, mute, room
selection, the Favorites / Sound / Settings icons, the preset chips, the tone sliders, every
toggle, the Releases link and Quit are all unreachable. The rooms list's arrow-key model
(`RoomsListView.swift:24-40`) cannot be entered either: `onMoveCommand` only fires when focus is
already inside that subtree, and nothing can put it there — the seeding branch at line 30-33 is
unreachable in practice. Only three things work: the global shortcut to open the panel, Escape to
close it (`PanelShellView.swift:28`), Cmd-[ for Back (`HeaderView.swift:21`) and Cmd-Q to quit
(`FooterView.swift:12`).

**Why it matters:** 2.1.1 is a Level A requirement and this is a complete block of one input
modality for every primary function of the app. The codebase already knows the mechanism — the
comment at `RoomRowView.swift:28-30` states it exactly ("Full Keyboard Access is off by default,
which leaves a plain macOS button untabbable") and applies `.focusable()` to fix it for that one
view. The fix was simply never generalised.

**Fix:**
1. Apply the `RoomRowView.swift:31` treatment consistently — add `.focusable()` to every custom
   control: `IconButton`, the header Back button, the transport buttons, `ToggleGlyph`, both
   mute buttons, `FavoriteRow`, the preset chips, the Settings refresh button and Quit.
2. Give the panel an initial focus target so the first keypress lands somewhere predictable:
   hoist a `@FocusState` into `PanelShellView` and use
   `.defaultFocus($focus, .playPause)` (or the selected room) on the root `VStack`.
3. Add panel-level `keyboardShortcut` bindings for the transport so play/pause and track skip do
   not depend on focus at all (e.g. `.keyboardShortcut(.space, modifiers: [])` on the play
   button, arrow-with-modifier for prev/next).
4. Verify with **System Settings → Keyboard → Keyboard navigation OFF** — that is the state the
   overwhelming majority of users are in, and the state the app must work in.

---

## Serious

### S1. Secondary and tertiary text is below the 4.5:1 minimum

**WCAG criterion:** 1.4.3 Contrast (Minimum) (Level AA)
**Instances:** 34 across 16 files

**(a) `.foregroundStyle(.secondary)` — 32 occurrences.** On macOS `secondaryLabelColor` is black
at 50% in light mode; over the panel's light background (~#ECECEC) that renders ≈ **3.85:1**,
below the 4.5:1 required for text under 18 pt. Dark mode (white at 55%) computes to ≈5.3:1 and
passes, so this is a **light-mode-only failure** — which makes it easy to miss in review.
Affected text that carries real meaning, not just chrome:
`Views/Main/HeroView.swift:23` (room name, and only 10 pt), `:28` (artist), `:34` ("Not playing"),
`Views/Main/ProgressBarView.swift:37` (elapsed / source / remaining),
`Views/Main/RoomRowView.swift:21` (the now-playing line for every room),
`Views/Components/SectionLabel.swift:18` (every section heading in the app),
`Views/Group/GroupScreen.swift:19,60,63`, `Views/Sound/SoundScreen.swift:54,71`,
`Views/Settings/SettingsScreen.swift:24,61`, `Views/StatusBannerView.swift:15,26`,
`Views/Shell/FooterView.swift:6,11` (the **Quit button label** is secondary — a control, not just
a caption).

**(b) `.foregroundStyle(.tertiary)` — `Views/Main/HeroView.swift:31`.** `tertiaryLabelColor` is
black at 26% light / white at 25% dark → ≈ **1.86:1 light, 2.25:1 dark**. The album / container
line is effectively invisible to anyone with reduced contrast sensitivity, in **both** appearances.

**(c) `Views/Sound/PresetChips.swift:36-37`.** A lit chip paints `Color.accentColor` text on
`Color.accentColor.opacity(0.22)`. With the default blue accent that is ≈ **2.60:1** at 11 pt.

**(d) `Views/Components/ErrorLine.swift:11`.** `systemRed` on the light panel is ≈ **3.0:1** at
`.caption` (11 pt). The highest-stakes text in the app — "Couldn't reach the speaker.",
"Not authorized…" (`App/AppState.swift:238-253`) — is the least legible. Same for
`Views/Settings/SettingsScreen.swift:46` (`loginError`).

**Fix:** stop using `.secondary` / `.tertiary` for anything the user must read. Define two app
tokens, e.g. `Color.primary.opacity(0.72)` for supporting text (≈5.2:1 light) and
`Color.primary.opacity(0.55)` for the faintest tier, verified in both appearances; reserve the
system semantic colours for genuinely decorative chrome. For (c) darken the lit chip text to a
fixed readable tone rather than the raw accent. For (d) use a darkened red
(`Color(nsColor: .systemRed).mix(with: .black, by: 0.25)` or equivalent) and raise the font to
`.callout`. Also read `@Environment(\.colorSchemeContrast)` and strengthen every tier when
Increase Contrast is on — the app currently ignores that setting entirely.

---

### S2. Errors, connection-status changes and loading states are never announced to VoiceOver

**WCAG criterion:** 4.1.3 Status Messages (Level AA)
**Files:** `App/AppState.swift:228-236`, `Views/Components/ErrorLine.swift:7-12`,
`Views/Main/RoomRowView.swift:51`, `Views/Favorites/FavoritesScreen.swift:42-44`,
`Views/Group/GroupScreen.swift:33`, `Views/Sound/SoundScreen.swift:76-78`,
`Views/Settings/SettingsScreen.swift:45-47`, `Views/StatusBannerView.swift:8-45`,
`Views/Sound/SoundScreen.swift:68-75`, `Views/Favorites/FavoritesScreen.swift:21-26`

**What a user experiences:** a VoiceOver user presses Play on the Kitchen row. The command fails.
A red line appears under the row and disappears three seconds later. VoiceOver says nothing at
all — the user is left believing the command worked and the speaker is simply silent. The same
silence covers: the status banner flipping from "Looking for Sonos…" to "No Sonos found on this
network" or "Authentication is switched on in the Sonos app"; the "Reading EQ…" spinner appearing
and being replaced by the tone sliders; the Favorites result count changing as the user types in
the search field (`FavoritesScreen.swift:25` — a correctly labelled element that is never
re-announced); and the Launch-at-login failure in Settings.

**Why it matters:** 4.1.3 requires that a status message which does not take focus is still
conveyed programmatically. Grep confirms **no announcement API is used anywhere in the app**.
Every one of these is a change the user caused and needs to know the outcome of.

**Fix:**
1. In `AppState.report(_:_:)` (`AppState.swift:228`), post the message directly after setting
   `rowErrors`: `AccessibilityNotification.Announcement(Self.message(for: error)).post()`.
2. In `AppState.apply(_:)`, post an announcement when `snapshot.status` transitions to a
   non-`.ready` value.
3. Mark the transient containers as live regions so VoiceOver picks up changes in place — add
   `.accessibilityAddTraits(.updatesFrequently)` to `ErrorLine`, the `StatusBannerView` banner,
   the "Reading EQ…" element (`SoundScreen.swift:74`) and the Favorites count
   (`FavoritesScreen.swift:22-25`).
4. Give the Favorites search field an `.accessibilityValue("\(filtered.count) results")` so the
   count is re-read as the user types.

---

### S3. The room row's Space-to-play action is invisible to VoiceOver, and the row's accessible name changes under the user

**WCAG criterion:** 4.1.2 Name, Role, Value (Level A); 2.1.1 Keyboard (Level A)
**File:** `Views/Main/RoomRowView.swift:16,33,34,35`

**What a user experiences:** each room row is a `Button` whose action is `select` (line 16), with
two raw key handlers bolted on: `.onKeyPress(.space)` toggles play/pause (line 33) and
`.onKeyPress(.return)` selects (line 34). VoiceOver activation (VO-Space) routes to the Button's
own action, so it **selects** — a VoiceOver user has no way whatsoever to reach the play/pause
behaviour of a row. There is also no hint telling any user that Space does something different
from Return.

Separately, Space on a focused macOS button conventionally *activates* it. Here it silently does
something else, so a sighted keyboard user who focuses a row and presses Space starts or stops
music when they expected to select the room.

Line 35 sets `.accessibilityLabel("\(group.name), \(line)")` where `line` is the live
now-playing text (`PlaybackDisplay.nowPlayingLine`). The element's **name** therefore changes
every time the track changes. Accessible names must be stable; changing content belongs in the
value. A VoiceOver user re-navigating the list after a track change hears different names for the
same rows, and any name-based navigation (typing to jump, Voice Control's "click Kitchen…")
breaks.

**Fix:**
```swift
.accessibilityLabel(group.name)
.accessibilityValue(line)
.accessibilityAddTraits(isSelected ? [.isSelected] : [])
.accessibilityHint("Press Space to play or pause")
.accessibilityAction(named: Text(group.playbackState == .playing ? "Pause" : "Play")) {
    state.togglePlayPause(group: group.id)
}
```
and move the Space binding onto a modifier key (or drop it) so plain Space keeps its
platform meaning of "activate the focused button".

---

### S4. Mute, Back and Clear-search targets are smaller than 24 × 24

**WCAG criterion:** 2.5.8 Target Size (Minimum) (Level AA, WCAG 2.2); macOS HIG minimum click
target
**Files:** `Views/VolumeSliderView.swift:68` (22 × 22, both the hero and compact mute buttons),
`Views/Shell/HeaderView.swift:17` (Back chevron, 22 × 22),
`Views/Components/SearchField.swift:14-19` (Clear button — no frame at all, so the target is the
`xmark.circle.fill` glyph's intrinsic size, roughly 14 pt),
`Views/Main/TransportView.swift:16-18,32-34` (previous / next — no frame; the target is the
18 pt glyph).

**What a user experiences:** users with tremor, limited fine motor control, or anyone on a
trackpad repeatedly misses the mute button in the rooms list — and the mute button sits 8 pt from
the volume slider, so a miss drags the volume instead of muting. The Clear-search glyph is the
smallest target in the app and abuts the text field.

**Why it matters:** 2.5.8 requires 24 × 24 CSS px unless the spacing exception applies. Mute
fails the exception (the slider target is well inside a 24 pt circle centred on it), as does
Clear. Previous/next arguably survive the spacing exception because the 22 pt gaps push the
neighbouring targets apart, but they are still the only transport controls in the app without an
explicit frame, while `IconButton` (28 × 28), `ToggleGlyph` (28 × 28) and the play button
(56 × 56) all have one — so this is inconsistency as much as it is a failure.

**Fix:** give every icon button an explicit `.frame(width: 28, height: 28)` plus
`.contentShape(Rectangle())` (the pattern already used at `IconButton.swift:14-16`). That covers
mute, Back, Clear, previous and next in one pass and brings them to the same 28 pt target as the
rest of the app.

---

### S5. Shuffle and Repeat signal "on" with accent colour alone

**WCAG criterion:** 1.4.1 Use of Color (Level A)
**File:** `Views/Main/TransportView.swift:59`

**What a user experiences:** the shuffle and repeat glyphs are identical in every way except
hue — `Color.accentColor` when on, `Color.secondary` when off. Computed against the light panel
those two colours are ≈3.40:1 and ≈3.85:1 respectively, i.e. **1.13:1 against each other**. They
are near-identical in lightness, so a user with any red/green or blue/yellow deficiency, or
anyone viewing in bright sun, cannot tell shuffle on from shuffle off. It collapses completely
for users who have set the system accent colour to Graphite, which renders as the same grey as
the off state.

**Fix:** add a non-colour cue. Either swap the symbol for a filled/circled variant when on
(`.symbolVariant(isOn ? .circle.fill : .none)`), or draw the same rounded background
`IconButton.swift:15` already uses for its active state, or add a small dot beneath the glyph.
Reading `@Environment(\.accessibilityDifferentiateWithoutColor)` and forcing the extra cue on is
the belt-and-braces version. The `.accessibilityValue("on"/"off")` at line 64 already handles
VoiceOver correctly — this finding is purely about the visual channel.

---

### S6. The progress bar re-announces every second and is not marked as frequently updating

**WCAG criterion:** 4.1.3 Status Messages (Level AA); 2.2.2 Pause, Stop, Hide (Level A, by
analogy — auto-updating content)
**Files:** `Views/Main/ProgressBarView.swift:11,26-28`, `App/AppState.swift:38-40,140-154`

**What a user experiences:** `let _ = state.tick` (line 11) makes this view re-render once per
second while the selected room is playing, and lines 26-28 build a fresh
`accessibilityValue("1:23 of 4:05")` each time. When a VoiceOver user's cursor rests on the
progress element, the changing value is re-announced roughly once a second and interrupts
whatever else VoiceOver was saying. A user trying to read the hero text or navigate the rooms
list beneath it is spoken over continuously for the whole track.

**Why it matters:** VoiceOver's contract for a value that changes on a timer is the
`updatesFrequently` trait, which tells it to poll on demand instead of interrupting. Grep
confirms the trait is not used anywhere in the app. The element also has no progress-indicator
trait, so it reads as plain static text rather than as a progress control.

**Fix:**
```swift
.accessibilityElement()
.accessibilityLabel("Progress")
.accessibilityValue("\(PlaybackDisplay.timeString(millis: position)) of \(PlaybackDisplay.timeString(millis: duration))")
.accessibilityAddTraits(.updatesFrequently)
```
Optionally coarsen the announced value to whole tens of seconds, and consider gating the tick
task in `AppState.updateTicking()` on `NSWorkspace.shared.isVoiceOverEnabled` so the once-a-second
churn is not paid at all during a VoiceOver session.

---

### S7. The Group screen hides the "will switch to this group" warning from VoiceOver

**WCAG criterion:** 1.3.1 Info and Relationships (Level A); 4.1.2 Name, Role, Value (Level A)
**File:** `Views/Group/GroupScreen.swift:57-66,76`

**What a user experiences:** each membership row shows the player name plus, when that room is
currently playing something else, the warning "Playing <track>, will switch to this group"
(line 62). The entire `VStack` holding the name **and that warning** is
`.accessibilityHidden(true)` (line 66), and the toggle's own label (line 76) is only
`"<player> in <group>"`. A VoiceOver user therefore toggles a room into the group with no
indication that they are about to interrupt music playing in another room. The same hiding also
drops "Source of this group" for non-coordinator context — though line 76 does recover that
particular string for the coordinator case.

**Why it matters:** hiding a container hides everything inside it. The warning exists precisely
because the consequence is not obvious, and it is withheld from exactly the users who cannot see
it on screen.

**Fix:** stop hiding the text; instead let it reach the toggle as value/hint:
```swift
.accessibilityLabel(player.name)
.accessibilityValue(isMember ? "In \(group.name)" : "Not in \(group.name)")
.accessibilityHint(
    isCoordinator ? "Source of this group"
    : playingElsewhere ? "Playing \(now.title); turning this on will switch it to this group"
    : ""
)
```
and drop the `.accessibilityHidden(true)` on the text stack (keeping it combined with the toggle
via `.accessibilityElement(children: .combine)` on the row if you want one stop).

---

## Moderate

### M1. Screen transitions strand the VoiceOver cursor and announce nothing

**WCAG criterion:** 2.4.3 Focus Order (Level A); 4.1.3 Status Messages (Level AA)
**Files:** `Views/Shell/PanelShellView.swift:36-47`, `App/AppState.swift:126-133`,
`Views/Sound/SoundScreen.swift:88-90`

Pressing a header icon replaces the entire body of the panel (`PanelShellView.swift:38-44`) with
no focus move and no screen-change notification. The VoiceOver cursor stays parked on the header
icon; the user must manually navigate down to discover what, if anything, changed. The same
happens in reverse on Back and on the icon's toggle-back-to-main behaviour
(`AppState.show(_:)`, line 126-131). On the Sound screen, changing the room picker re-fires
`.task(id: playerID)` (line 88), tearing down and rebuilding the EQ subtree — any cursor inside it
is lost back to the top of the panel.

**Fix:** post `AccessibilityNotification.ScreenChanged(...)` (or `.LayoutChanged`) on
`state.screen` changes, naming the new screen's first element, and drive focus explicitly with
`@AccessibilityFocusState` anchored to the screen title. For the Sound screen, keep the card
scaffold mounted and swap only its contents so focus survives a picker change.

### M2. Rooms, Favorites, Group and Sound rows carry no list semantics

**WCAG criterion:** 1.3.1 Info and Relationships (Level A)
**Files:** `Views/Main/RoomsListView.swift:20-22`, `Views/Favorites/FavoritesScreen.swift:34-40`,
`Views/Group/GroupScreen.swift:28-32`, `Views/Components/Card.swift:4-27`

Every collection in the app is a `ForEach` inside a plain `VStack` (or inside `Card`, which is
itself a plain `VStack`). VoiceOver announces neither the container nor position-in-set, so a user
hears a run of loose buttons with no "list, 6 items" and no "3 of 6" — they cannot tell how many
rooms or favourites exist, or where they are in the run, without walking to the end.

**Fix:** wrap each collection in
`.accessibilityElement(children: .contain).accessibilityLabel("Rooms")` at minimum; better, use a
real `List` (or `LazyVStack` inside an `accessibilityElement(children: .contain)` container) so
AppKit emits proper row indices.

### M3. Every font is a fixed point size, so text never responds to the system text-size setting

**WCAG criterion:** 1.4.4 Resize Text (Level AA)
**Files:** 14 `.system(size:)` call sites —
`Views/Main/HeroView.swift:21,26,34`, `Views/Main/TransportView.swift:17,25,33,58`,
`Views/Shell/HeaderView.swift:11,17,24`, `Views/Components/SectionLabel.swift:16`,
`Views/Components/IconButton.swift:13`, `Views/Favorites/FavoriteRow.swift:21`,
`Views/VolumeSliderView.swift:67`

`Font.system(size:)` without `relativeTo:` is an absolute size and ignores the user's text-size
preference entirely. The smallest is the hero's room name at **10 pt**
(`HeroView.swift:21`), followed by section headings at 11 pt with 1.2 pt letter-spacing
(`SectionLabel.swift:16`). Even if the sizes did scale, three fixed-height frames would clip the
result: the header at 44 pt (`HeaderView.swift:36`), the hero at 96 pt (`HeroView.swift:40`) and
the tone-value readout at 30 pt (`ToneSlider.swift:24`).

**Fix:** use `.font(.system(size: 11, relativeTo: .caption))` (or the text styles directly) so
sizes track the system setting, and replace the fixed `.frame(height:)` values with
`minHeight`/`idealHeight` so the rows can grow. `@ScaledMetric` is the idiomatic way to scale the
icon frames alongside.

### M4. `lineLimit(1)` inside a fixed 420 pt panel truncates content with no way to read it

**WCAG criterion:** 1.4.4 Resize Text (Level AA); 1.4.10 Reflow (Level AA)
**Files:** `Views/Main/HeroView.swift:26,28,31`, `Views/Main/RoomRowView.swift:20,21`,
`Views/Favorites/FavoriteRow.swift:14,16`, `Views/Group/GroupScreen.swift:18,19,63`,
`Views/Main/ProgressBarView.swift:32,42`, `Views/Shell/PanelShellView.swift:19,27`

The panel width is hard-coded to 420 pt in two places and every title, artist, album, room name
and now-playing line is capped at one line. Long track titles and long room names truncate with an
ellipsis and there is no tooltip, no marquee and no expanded view, so the information is simply
lost to sighted users. (VoiceOver is unaffected — SwiftUI exposes the full string regardless of
visual truncation — which is why this is Moderate rather than Serious.) The problem compounds
with M3: any increase in text size truncates more.

**Fix:** add `.help(now.title)` to every truncating `Text` so the full value is available on
hover, and allow two lines for the hero title. Consider widening the panel or letting it grow to
the `maximumBodyHeight` budget already defined at `PanelShellView.swift:11`.

### M5. Reduce Motion is not honoured

**WCAG criterion:** 2.3.3 Animation from Interactions (Level AAA); macOS HIG — Motion
**File:** `Views/Shell/PanelShellView.swift:39-46`

Every screen change slides the whole 420 pt body horizontally
(`.transition(.move(edge:))`) over 0.2 s, and the panel's own height animates with it as
`bodyHeight` changes (line 20-22). Nothing reads
`@Environment(\.accessibilityReduceMotion)`, so users who have switched Reduce Motion on — often
precisely because sliding panes trigger vestibular symptoms — still get the slide.

**Fix:**
```swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion
…
.animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: state.screen)
```
and substitute `.opacity` for `.move` when `reduceMotion` is true.

### M6. Double-click-to-zero on the tone sliders is mouse-only

**WCAG criterion:** 2.1.1 Keyboard (Level A)
**File:** `Views/Sound/ToneSlider.swift:20`

`.onTapGesture(count: 2) { local = 0; onChange(0) }` is the only way to zero an individual band.
There is no keyboard equivalent and no VoiceOver action; the Reset button
(`SoundScreen.swift:27`) zeroes bass, treble **and** sub together, so it is not a substitute.

**Fix:** add `.accessibilityAction(named: Text("Reset \(label)")) { local = 0; onChange(0) }`,
which surfaces it in the VoiceOver rotor and to Voice Control at the same time.

### M7. The "Custom" chip looks and reads like a selectable chip but is inert

**WCAG criterion:** 4.1.2 Name, Role, Value (Level A)
**File:** `Views/Sound/PresetChips.swift:18-19`

Flat / Warm / Bright are `Button`s carrying the `.isSelected` trait (lines 11-16). "Custom" is a
bare `Chip` — a `Text` — styled identically and lit the same way. Visually it is indistinguishable
from the three real chips, so users click it and nothing happens. For VoiceOver it reads as static
text with no button role, and the selected state is **hardcoded into the name**
(`current == nil ? "Custom, selected" : "Custom"`) rather than expressed as the `.isSelected`
trait the sibling chips use — so it reads inconsistently, cannot be filtered by the rotor's button
list, and will read the word "selected" even at verbosity settings where the user has asked not to
hear it.

**Fix:** either render Custom visually distinct (drop the capsule, make it a plain caption), or
make it a disabled `Button` so VoiceOver announces "Custom, selected, button, dimmed" and the
state comes from the trait:
```swift
Button {} label: { Chip(title: "Custom", lit: current == nil) }
    .disabled(true)
    .accessibilityLabel("Custom")
    .accessibilityAddTraits(current == nil ? [.isSelected] : [])
```

### M8. `RoomPicker` can render and announce an empty selection

**WCAG criterion:** 4.1.2 Name, Role, Value (Level A)
**Files:** `Views/Components/RoomPicker.swift:10-13`,
`Views/Favorites/FavoritesScreen.swift:9,17`, `Views/Sound/SoundScreen.swift:20`

The picker's `selection` is `String?` but the option list (line 11-13) never contains a `nil` tag.
When `favoritesTargetGroupID` / `soundPlayerID` is nil, no option matches, the menu button renders
blank and VoiceOver announces "Play to, pop up button" with **no value**. The Favorites screen
makes this worse by computing a safe fallback for the *action*
(`targetGroupID` at line 9, `?? state.selectedGroupID`) while binding the picker to the raw
optional at line 17 — so the picker can display nothing while playing a favourite still works.

**Fix:** bind the picker to the same resolved value the action uses, or add an explicit
placeholder row (`Text("Choose a room").tag(String?.none)`) so there is always a matching tag and
always a spoken value.

### M9. Inline errors vanish after three seconds with no way to re-read them

**WCAG criterion:** 2.2.1 Timing Adjustable (Level A)
**File:** `App/AppState.swift:53,228-236`

`clearDelay` defaults to 3 s and `report(_:_:)` schedules an unconditional clear. Three seconds is
below the time a screen-magnifier user needs to find the message, and well below what a slow
reader needs for "Not authorized. Check the Sonos app's connection security settings."
(line 242). Once cleared, the message is unrecoverable — there is no log or history anywhere in
the app.

**Fix:** raise the default to at least 8 s, or keep the error visible until the next successful
command on that group, or add a dismiss affordance. If S2 is implemented, the announcement covers
VoiceOver users, but the visual timing still needs to change for low-vision users.

### M10. Input and surface boundaries fall below 3:1

**WCAG criterion:** 1.4.11 Non-text Contrast (Level AA)
**Files:** `Views/Components/SearchField.swift:23`, `Views/Components/Card.swift:9`,
`Views/StatusBannerView.swift:63`

The search field — an actual input control, which 1.4.11 explicitly covers — is delimited only by
`.quaternary.opacity(0.5)`, i.e. black at roughly 5% over the panel. That is well under 3:1, so
the field's boundary is essentially invisible; a low-vision user cannot tell where to click to
type. The same fill delimits `Card` and the status banner, which are grouping surfaces rather than
controls (1.4.11 does not strictly apply) but read as equally indistinct.

**Fix:** give `SearchField` a real border —
`.overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.25)))` — and
strengthen it further when `@Environment(\.colorSchemeContrast) == .increased`.

---

## Minor

### m1. No `accessibilityHint` anywhere in the app
`grep` finds zero uses. Several behaviours are not inferable from the name alone:
pressing the already-active header icon returns to Main (`App/AppState.swift:126-127`,
`Views/Components/IconButton.swift:19-20`); a fixed-volume line-out disables the slider with no
stated reason (`Views/VolumeSliderView.swift:36`); the Releases row leaves the app for a browser
(`Views/Settings/SettingsScreen.swift:64-73`); the shortcut recorder captures keystrokes while
armed (`Views/Settings/SettingsScreen.swift:51`), which will swallow VoiceOver commands.
**Fix:** add a one-clause `.accessibilityHint` to each.

### m2. Uppercase display strings are used as accessible names
`App/Screen.swift:7-15` ("SONOS", "FAVORITES", "SOUND", "SETTINGS"),
`Views/Components/SectionLabel.swift:15` (call sites pass "ROOMS", "TONE", "PLAY TO",
"ALL FAVORITES", "ROOMS PLAYING TOGETHER"), and `Views/Main/HeroView.swift:19`
(`group.name.uppercased()` — so a room genuinely named "TV" or "Sal" enters the accessibility
tree in caps). VoiceOver spells out short all-caps tokens as initialisms. `Screen.accessibilityName`
(line 17-25) already holds the correctly-cased version and is used for the icon buttons — it just
isn't used for the titles.
**Fix:** style with `.textCase(.uppercase)` and keep the real string in the accessibility label;
use `Screen.accessibilityName` for the header title's label.

### m3. `FavoriteRow` drops its second line from the accessible name
`Views/Favorites/FavoriteRow.swift:28` announces only "Play <name>". The visible second line
("Sveriges Radio · Station", `FavoriteRow.swift:54-56`) is what distinguishes two favourites with
similar names, and it is lost.
**Fix:** add `.accessibilityValue(favorite.secondLine)`.

### m4. Arrow glyphs in the banner instructions are read aloud as "right arrow"
`Views/StatusBannerView.swift:34,41` — "Settings → System → Network → Connection security" becomes
"Settings right arrow System right arrow Network right arrow Connection security".
**Fix:** supply an `.accessibilityLabel` with the path spelled using the word "then".

### m5. Shuffle / Repeat state uses a value string without a matching trait
`Views/Main/TransportView.swift:63-64` sets `.accessibilityValue("on"/"off")` on a `Button`, while
`Views/Components/IconButton.swift:20`, `Views/Main/RoomRowView.swift:36` and
`Views/Sound/PresetChips.swift:16` all use `.isSelected` for the equivalent concept — three
different spellings of "this control is on" across one panel.
**Fix:** standardise on `.isSelected` (or convert the two glyphs to real `Toggle`s, which
announce "on/off, switch" natively).

### m6. The search field is labelled only by its placeholder, and the Clear button changes tab order
`Views/Components/SearchField.swift:10,13` — `prompt` serves as placeholder *and*
`accessibilityLabel`, so VoiceOver is fine but the visible label disappears as soon as the user
types (a 3.3.2 Labels or Instructions concern). The Clear button only exists while `text` is
non-empty, so the focus order changes mid-typing.
**Fix:** keep a persistent visible label above the field, or accept the placeholder and always
render the Clear button (disabled when empty).

### m7. The hero does not expose playback state
`Views/Main/HeroView.swift:43` combines room, title, artist and album into one element with no
indication of whether the track is playing or paused. The state is only inferable from the
Play/Pause button's inverted label further down (`TransportView.swift:30`).
**Fix:** append the state to the combined element's value.

### m8. The Loudness description floats loose, ahead of the control it describes
`Views/Sound/SoundScreen.swift:53-64` hides the "Loudness" title (line 53) but leaves
"Boosts bass and treble at low volume" (line 54) as an independent element, so VoiceOver reads the
explanation *before* it knows what is being explained. This is also the opposite convention from
`GroupScreen.swift:66`, which hides its whole descriptive stack.
**Fix:** move the sentence into `.accessibilityHint` on the toggle and hide the text, matching one
convention across both screens.

### m9. Tone slider values are announced as bare signed numbers using U+2212
`Views/Sound/ToneSlider.swift:19` with `App/TonePreset.swift:28-34` — VoiceOver reads "plus 3" /
"minus 2" with no unit, so a user cannot tell whether the range is ±10 steps or ±10 dB.
**Fix:** build the accessibility value separately from the display string, e.g.
`.accessibilityValue("\(value) of \(range.lowerBound) to \(range.upperBound)")`.

### m10. Disabled controls dim to roughly 1.6:1
`Views/Main/TransportView.swift:59` (`Color.secondary.opacity(0.4)`) and
`Views/Main/RoomsListView.swift:16` (`Color.accentColor.opacity(0.4)`) render at about 1.6:1
against the light panel. WCAG exempts disabled controls from contrast, and VoiceOver correctly
says "dimmed" via `.disabled(_:)`, so this is not a failure — but at that level the glyph is
invisible rather than merely de-emphasised, and a low-vision user cannot tell an unavailable
shuffle from an off shuffle.
**Fix:** dim to ~0.55 rather than 0.4, and strengthen under Increase Contrast.

### m11. The Favorites row's play glyph looks like a separate button
`Views/Favorites/FavoriteRow.swift:20-23` draws a `play.fill` in a 28 × 28 frame inside the row
button. It is correctly not focusable (so there is no duplicate VoiceOver stop — see Done Well),
but it reads visually as an independent control, inviting users to aim at the one part of the row
that is no more clickable than the rest.
**Fix:** reduce its visual weight, or move it to a hover-revealed affordance.

---

## What is done well — keep this

**Decorative content is hidden, consistently and deliberately.**
`Views/Artwork.swift:22` hides *all* artwork at the component level, so every one of its six call
sites inherits the right behaviour. `Views/StatusBannerView.swift:58` and
`Views/Settings/SettingsScreen.swift:20` hide the coloured status dots — and in both cases the
same information is carried in adjacent text ("Connected" / "No Sonos found"), so the app never
relies on the green/grey dot alone. `Views/Components/SearchField.swift:9` hides the magnifier.

**Visible duplicates are suppressed so VoiceOver gets exactly one stop per control.**
`Views/Main/ProgressBarView.swift:30,34` hide the elapsed and remaining readouts because the same
values are already in the bar's `accessibilityValue`; `Views/VolumeSliderView.swift:53` hides the
numeric volume; `Views/Sound/ToneSlider.swift:14,25` hide both the label and the readout because
the slider carries them; `Views/Sound/SoundScreen.swift:53` and
`Views/Settings/SettingsScreen.swift:38` hide the text label that the adjacent toggle already
names. This is the single most consistently-applied good practice in the codebase.

**The `combine: false` escape hatch in the status banner is exactly right — and documented.**
`Views/StatusBannerView.swift:19-22` and `:51-53`:
> "combine: false — this banner has a real interactive control (Retry); combining would demote it
> from a focusable button to, at best, an activate action on the merged text."

That is precisely the trade-off, reasoned correctly, written down at the point of use.

**Headers are marked.** `Views/Components/SectionLabel.swift:19` applies `.isHeader` once, so every
section heading in every screen inherits it; `Views/Shell/HeaderView.swift:14,26` mark the panel
title on both the main and sub-screen branches.

**Selected state uses the trait, not just colour.** `Views/Components/IconButton.swift:20`,
`Views/Main/RoomRowView.swift:36` and `Views/Sound/PresetChips.swift:16` all add `.isSelected`.

**The keyboard-reachability problem was diagnosed correctly, in a comment, at the one place it was
fixed.** `Views/Main/RoomRowView.swift:28-31` — the `.focusable()` treatment and its rationale.
C1 is entirely about generalising this, not discovering it.

**The volume slider is deliberately kept outside the room row's button.**
`Views/Main/RoomRowView.swift:38-45` — the slider is a sibling of the selection button rather than
a child, so it stays an independently focusable control instead of being swallowed. The file's own
header comment states the intent: "Art and text select; the slider does not."

**Slider and mute labels are room-scoped and state-aware.** `Views/VolumeSliderView.swift:37-38`
produces "Kitchen volume, 42 percent, muted" — the mute state rides on the slider's value rather
than needing a separate stop — and `:71` names both the action and the room
("Unmute Kitchen"), so the label is unambiguous when several sliders are on screen at once.

**A disabled control explains itself.** `Views/Group/GroupScreen.swift:76` names the coordinator's
toggle "…, source of this group", so a VoiceOver user hearing "dimmed" also hears *why*.

**Standard dismissal and navigation keys are wired.** `Views/Shell/PanelShellView.swift:28`
(Escape closes the panel), `Views/Shell/HeaderView.swift:21` (Cmd-[ for Back — the platform
convention), `Views/Shell/FooterView.swift:12` (Cmd-Q). There is no keyboard trap anywhere in the
app.

**2.5.3 Label in Name is respected throughout.** Every place a visible label is augmented, the
visible words survive into the accessible name: "Group" → "Group rooms"
(`RoomsListView.swift:18`), "Reset" → "Reset tone for Kitchen" (`SoundScreen.swift:29`),
"Releases" → "Releases on GitHub" (`SettingsScreen.swift:73`), "Loudness" → "Loudness for Kitchen"
(`SoundScreen.swift:64`). Voice Control users can say what they see.

**The once-a-second tick is tightly scoped.** `App/AppState.swift:140-154` starts the tick task
only when the panel is visible *and* the selected group is actually playing, and cancels it
otherwise; `PanelShellView.swift:29,33` covers both teardown paths. Because `tick` is read in
exactly one view (`ProgressBarView.swift:11`), the `@Observable` graph confines the re-render to
that subtree — which is why S6 is a single-element problem rather than the whole panel churning
under the VoiceOver cursor every second.

**A bare number got a meaningful label.** `Views/Favorites/FavoritesScreen.swift:25` turns the
count "12" into "12 favorites".

**The menu bar item itself is named.** `App/SonosRemoteApp.swift:23` —
`MenuBarExtra("Sonos", systemImage:)` gives the status item an accessible name, so VoiceOver users
can find it in the menu bar.

---

## Recommended Next Steps — prioritised top 5

1. **Make the panel keyboard-operable with Full Keyboard Access off (C1).** Add `.focusable()` to
   every custom control — generalising the fix already at `RoomRowView.swift:31` — give the panel
   an initial focus target with `.defaultFocus`, and add panel-level `keyboardShortcut`s for the
   transport. This is the one Critical finding and it unblocks the rooms list's arrow-key model as
   a side effect. Verify with keyboard navigation switched **off**.

2. **Announce errors, status changes and loading states (S2).** One line in
   `AppState.report(_:_:)` (`AppState.swift:231`) plus a status-transition announcement in
   `apply(_:)` and `.updatesFrequently` on the four transient containers. Highest
   value-per-line-changed in the whole audit: it converts four separate silent-failure paths into
   spoken feedback.

3. **Fix the contrast tiers (S1).** Replace `.secondary` (32 sites) and `.tertiary` (1 site) with
   two app-defined tokens verified in light *and* dark, darken the error red
   (`ErrorLine.swift:11`) and the lit preset chip (`PresetChips.swift:36-37`), then read
   `colorSchemeContrast` to strengthen everything under Increase Contrast. Note that the
   `.secondary` failure is light-mode-only, so test in light mode explicitly.

4. **Repair the room row's interaction contract (S3) and expose the Group screen's warning (S7).**
   Both are cases where a VoiceOver user can reach a control but not its real behaviour or its real
   consequence: add `.accessibilityAction(named: "Play")` to the row, split its label from its
   changing value, and move the "will switch to this group" text out of the hidden stack into the
   toggle's hint.

5. **Raise the small targets to 28 × 28 (S4) and give shuffle/repeat a non-colour "on" cue (S5).**
   Five `.frame(width: 28, height: 28)` additions — mute (×2), Back, Clear, previous/next — plus a
   symbol-variant or background change on the two toggle glyphs. Both are small, mechanical, and
   close a Level AA and a Level A criterion respectively.
