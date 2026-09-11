# Panel redesign, round 1: design spec

Date: 2026-09-11. Status: approved in brainstorming, awaiting written review.

Supersedes the panel layout in `docs/superpowers/specs/2026-09-04-sonos-remote-design.md` §5. Everything else in that spec (SonosKit architecture, discovery, resilience, signing) still applies. The visual reference is the owner's mockup of four screens, main, Favorites, Sound, and Settings, at `docs/design/2026-09-11-panel-mockup.png`.

## 1. Goal

Replace the "list of rows, one open" panel with the mockup's design: a hero for one selected room, a compact rooms list, and four sub-screens reached from header icons. Deliver the new look for everything the app already does, plus the cheap additions the screens read from data already available (progress bar, shuffle and repeat, tone presets, favorites search, connection card, version and releases link).

### In scope (round 1)

- Shell: 420 pt panel, header with screen icons, back navigation, animated screen switch, footer with version and Quit.
- Main screen: hero with artwork, room, title, artist, album; progress bar with elapsed and remaining times and a source line; transport with shuffle, previous, play/pause, next, repeat; group volume; rooms list with per-group slider and selection; "Group" link.
- Favorites screen: play-to room picker, search, list with type glyphs, play.
- Sound screen: tuning player picker, presets, tone card with Reset, Loudness card.
- Group screen: membership switches for the selected room.
- Settings screen: connection card with refresh, launch at login, global shortcut, version, releases link. The separate Settings window is removed.
- SonosKit: playback position, duration, play modes in the snapshot; shuffle and repeat commands; software version in the snapshot.

### Out of scope (round 2 candidates)

Seek by dragging the progress bar, pinned favorites, balance, Speech Enhancement, Night Sound, album art in the menu bar, volume step and fine-volume settings, confirm before grouping, default room, streaming services, diagnostics, in-app update checks, the household name.

## 2. Decisions

| Decision | Choice | Why |
|---|---|---|
| Navigation | One `Screen` enum (`main`, `favorites`, `sound`, `group`, `settings`) switched by the header icons and a back chevron; slide transition | Predictable in a menu bar window; the design is one level deep |
| Selection model | One `selectedGroupID` drives every screen; replaces `openGroupID` | Matches the hero + list layout |
| Width | 420 pt | Mockup proportions |
| Appearance | System materials and colours; follows light and dark mode; the mockup's dark look is the reference | Native look decision from the original spec |
| Header title | Uppercase "SONOS" on the main screen, as designed | Owner's design; the app name stays "Remote for Sonos" elsewhere |
| Shuffle and repeat | Included in round 1 | State already arrives in every playback event; toggling is one command |
| Settings window | Removed; settings live on the Settings screen | Removes the fragile activation-policy code |

## 3. Shell

- **Header** (44 pt). Main screen: left `Text("SONOS")` in small uppercase with letter spacing, secondary colour. Right: three `IconButton`s, `heart`, `slider.horizontal.3`, `gearshape`, each 28 pt square with a rounded background when it is the active screen. Sub-screens: left is a back `chevron.left` button, a 22 pt `Artwork` of the selected room, and the screen name in the same uppercase style ("FAVORITES", "SOUND", "GROUP", "SETTINGS"); the three icons stay on the right. Accessibility: the title row is a header; each icon button is labelled with the screen name; the back button is "Back".
- **Body**: the current screen's view. Switching animates with `.transition(.move(edge:))` sliding right-to-left when entering a sub-screen and left-to-right when returning, over 0.2 s. The body measures its content height (the existing `onGeometryChange` technique) and the panel animates to it, capped at 640 pt with scrolling beyond that.
- **Footer**: "Remote for Sonos <CFBundleShortVersionString>" left in secondary caption, "Quit" right (⌘Q). Divider above.
- **Escape** closes the panel from any screen. **Cmd-[** or the back button returns to main. Opening the panel always shows the screen that was last visible in this session; the app launches on main.

## 4. Main screen

- **Hero**: `HStack` of a 96 pt `Artwork` (placeholder glyph when no art) and a text column: a row with `hifispeaker` glyph and the room name in uppercase secondary caption; title in `.title3.weight(.semibold)`, one line, truncated; artist in body secondary; album (or container name when the item has no album) in caption tertiary. When nothing is playing: title "Not playing", no artist or album.
- **Progress**: a 3 pt rounded bar spanning the hero's width, filled fraction = position ÷ duration. Elapsed on the left, remaining (negative, "−3:08") on the right, both in monospaced caption; the source line ("Spotify · Soft Evening Mix", from `serviceName · containerName`) centred between them. When duration is unknown (radio) the bar and times are hidden and only the source line shows. Position is extrapolated locally: `position = reportedPosition + (now − reportedAt)` while the state is playing, clamped to the duration; frozen otherwise. A one-second timer in `AppState` refreshes the display while the selected room is playing and the panel is open.
- **Transport**: five buttons in a row, centred, borderless: `shuffle` (accent colour when on), `backward.end.fill`, a 56 pt circle with `pause.fill` or `play.fill`, `forward.end.fill`, `repeat` (accent when on). Shuffle and repeat toggle via the new commands; they are disabled when the speaker reports it cannot shuffle or repeat. Labels: "Shuffle", "Previous track", "Play"/"Pause", "Next track", "Repeat", with values "on"/"off" for the toggles.
- **Volume**: `speaker.wave.1` glyph, the group volume slider (existing `VolumeSliderView` in a variant without label), numeric value right-aligned in monospaced digits. Mute stays on the glyph as a button.
- **Rooms**: section label "ROOMS" left, "Group" link with `link` glyph right, opening the Group screen. Rows are groups sorted playing-first then by name (existing `orderedGroups`). Row: 40 pt `Artwork` of the group's now playing (speaker glyph placeholder), name in semibold, second line = "title" for a playing or paused group else "Not playing" (radio: container name), then a compact slider (existing compact mode). The selected group's row has a subtle rounded background. Clicking the art or text selects the group; the slider does not. Rows are focusable; Up/Down move, Return selects, Space toggles play on the focused group.
- **States**: `StatusBannerView` unchanged in behaviour, restyled to the card look; when there are no groups the hero shows "No room selected" and the transport is disabled.

## 5. Sub-screens

Shared components: `SectionLabel` (uppercase caption with letter spacing, optional trailing view), `Card` (rounded 10 pt background using `.quaternary` fill, 1 pt separator between rows), `RoomPicker` (a `Picker` with `.menu` style showing a `hifispeaker` glyph and the name).

### Favorites

- Row 1: `SectionLabel("PLAY TO")` with a `RoomPicker` over `orderedGroups`, bound to `favoritesTargetGroupID`, initialised to `selectedGroupID` each time the screen opens.
- Row 2: search `TextField` with a magnifying-glass glyph, placeholder "Search favorites", bound to `favoritesSearch`; filters by case-insensitive containment in name or subtitle. Clearing the text restores the full list.
- Row 3: `SectionLabel("ALL FAVORITES")` with the count of the filtered list on the right.
- List: one row per favorite: 40 pt `Artwork` or a type glyph (`dot.radiowaves.left.and.right` for stations, `music.note.list` for playlists, `opticaldisc` for albums, `music.note` otherwise; the type comes from the favorite's `resource.type`, added to `Favorite` as `kind`), name, subtitle ("Sveriges Radio · Station"), and a `play.fill` button. Row or button plays the favorite on the target group. Empty list: "No favorites match" when searching, "No favorites in your Sonos system yet" otherwise.

### Sound

- Row 1: `SectionLabel("TUNING")` with a `RoomPicker` over all players, bound to `soundPlayerID`, initialised to the selected group's coordinator when the screen opens.
- Row 2: chips Flat, Warm, Bright, Custom in a segmented-like row of capsule buttons. Presets: Flat bass 0 treble 0; Warm bass +3 treble −2; Bright bass −2 treble +3. The lit chip is the preset whose values match the current EQ, else Custom. Choosing a preset writes both values through `updateEQ`.
- Card "TONE" with a Reset link (`arrow.counterclockwise` + "Reset") that writes bass 0, treble 0, sub 0 where present. Rows: Bass, Treble, Sub (only when the player has a sub), each a slider with the value right-aligned ("−2", "+1", "0") in monospaced digits. Double-click still resets one slider.
- Card with Loudness: title, one-line description "Boosts bass and treble at low volume", switch on the right.
- "Reading EQ…" placeholder with a spinner until the values load, as today.

### Group

- Small hero: 40 pt artwork, room name, now-playing line.
- `SectionLabel("ROOMS PLAYING TOGETHER")` and a card with one row per player: name, optional note, switch on the right. Coordinator on and disabled with "Source of this group". A player currently playing elsewhere shows "Playing <title>, will switch to this group". Switches call the existing `setMembership`.

### Settings

- Connection card: green dot and "Connected" when status is ready, grey dot and the status text otherwise ("Looking for Sonos…", "No Sonos found", "Not authorized", "Local network access is off"); second line "<n> speakers · S2 · <softwareVersion>"; a refresh button (`arrow.clockwise`, label "Refresh connection") calling `retryDiscovery`.
- `SectionLabel("GENERAL")` card: "Launch at login" with a switch (existing `SMAppService` logic, including the re-entry guard and error text); "Global shortcut" with the `KeyboardShortcuts.Recorder` on the right.
- `SectionLabel("SYSTEM")` card: "Version" with "<short version> (<build>)" on the right; "Releases" row opening `https://github.com/jens-wedin/sonos-remote/releases` in the browser.
- The `Window` scene, `SettingsOpener`, and `SettingsView` are deleted.

## 6. SonosKit changes

- `Group` gains `progress: PlaybackProgress` where `PlaybackProgress { positionMillis: Int; durationMillis: Int?; reportedAt: Date; shuffle: Bool; repeatEnabled: Bool; canShuffle: Bool; canRepeat: Bool }` (`repeat` is a Swift keyword, hence `repeatEnabled`). The reducer fills `positionMillis`, `shuffle`, `repeatEnabled`, `canShuffle`, `canRepeat` from `playbackStatus` events (`positionMillis`, `playModes`, `availablePlaybackActions`) and `durationMillis` from `metadataStatus` (`currentItem.track.durationMillis`), stamping `reportedAt` from an injected clock so tests are deterministic.
- `Favorite` gains `kind: Kind` (`station`, `playlist`, `album`, `other`) mapped from `resource.type` (`STREAM` → station, `PLAYLIST` → playlist, `ALBUM` → album, anything else → other).
- `HouseholdSnapshot` gains `softwareVersion: String?`, the gateway player's `softwareVersion` from the groups response.
- `LocalAPIClient` gains `setPlayModes(shuffle:repeat:groupID:at:)` posting `{"playModes": {"shuffle": …, "repeat": …}}` to `/groups/{gid}/playback/playMode`; `Household` gains `setShuffle(_:group:)` and `setRepeat(_:group:)`, each sending the full pair with the other value unchanged, via `groupCommand` with the coordinator retry.
- Wire types: `WirePlaybackStatus` gains `positionMillis`, `playModes {shuffle, repeat}`, `availablePlaybackActions {canShuffle, canRepeat}`; `WireTrack` gains `durationMillis`; `WireFavorite` gains `resource { type }`; `WirePlayer` gains `softwareVersion`.

## 7. App state

- `selectedGroupID` replaces `openGroupID` (same UserDefaults key semantics under a new key `selectedGroupID`; the old key is ignored). `RowOpenPolicy` is renamed `SelectionPolicy` with identical rules: keep the selection if it exists; on first snapshot or when it vanished, remembered id → first playing → first group; a topology change re-resolves only when nothing is selected. There is no "closed" state any more: with groups present, something is always selected.
- `screen: Screen = .main`, `favoritesSearch: String`, `favoritesTargetGroupID: String?`, `soundPlayerID: String?`.
- `displayedPosition(for group: Group, now: Date) -> Int?` is a pure function used by the view; a `Timer`-driven `tick` counter in `AppState` invalidates the view once a second while the selected group is playing and the panel is visible (the panel controller's `isPresented` gates it).
- Presets live in `TonePreset` (pure): `static let all`, `func matches(_ eq: EQSettings) -> Bool`, `static func current(for eq: EQSettings) -> TonePreset?`.
- Favorites filtering is a pure function `FavoritesFilter.apply(_:query:)`.

## 8. Testing

- SonosKit: reducer tests for progress and play-mode fields from the `events.jsonl` fixture (position 133000, shuffle false, canShuffle true, duration 246000 from the metadata fixture); `Favorite.kind` mapping from `favorites.json` (station); `softwareVersion` from `groups.json` ("96.1-79270"); client tests for the play-mode request body; household tests that `setShuffle` posts to the coordinator with repeat preserved.
- App: `SelectionPolicy` tests (renamed from the existing ones); `AppState` tests for screen switching and back; `FavoritesFilter` tests; `TonePreset` tests; `displayedPosition` tests (playing extrapolates and clamps; paused freezes; nil duration → nil).
- Manual checklist gains: header navigation, progress bar ticking, shuffle/repeat, favorites search, presets and Reset, connection card refresh, and the removal of the Settings window.

## 9. Files

New: `SonosRemote/App/Screen.swift`, `SelectionPolicy.swift` (renamed), `TonePreset.swift`, `FavoritesFilter.swift`, `PlaybackDisplay.swift`; `SonosRemote/Views/Shell/PanelShellView.swift`, `HeaderView.swift`, `FooterView.swift` (moved), `Components/{SectionLabel,Card,RoomPicker,IconButton}.swift`; `Views/Main/{MainScreen,HeroView,ProgressView,TransportView,RoomsListView,RoomRowView}.swift`; `Views/Favorites/FavoritesScreen.swift`; `Views/Sound/SoundScreen.swift`; `Views/Group/GroupScreen.swift`; `Views/Settings/SettingsScreen.swift`.

Deleted: `OpenRowView.swift`, `ClosedRowView.swift`, `GroupRowView.swift`, `FavoritesTabView.swift`, `EQTabView.swift`, `GroupTabView.swift`, `SettingsView.swift`, `SettingsOpener.swift`, `RowOpenPolicy.swift` (renamed).

Kept: `VolumeSliderView.swift`, `Artwork.swift`, `StatusBannerView.swift`, `VolumeCommandGate.swift`, `PanelController.swift`, `SonosGroupAlias.swift`.

## 10. Risks

- Animated height changes in the menu bar window may flicker; mitigated by measuring content height as the list does today. If it still flickers, disable the height animation and keep only the slide.
- Removing the Settings window removes ⌘, but the app has no menu bar, so nothing is lost.
- The progress timer must stop when the panel closes to avoid waking the app every second all day.
