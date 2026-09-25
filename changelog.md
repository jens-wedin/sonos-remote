# Changelog

All notable changes to this project are documented here. Format follows Keep a Changelog; versions follow SemVer.

## [Unreleased]

## [0.2.4] - 2026-09-25

### Added
- A yellow "Can't verify <room>" banner (and a VoiceOver announcement) when a speaker's certificate is rejected, instead of the room silently showing no music.

### Changed
- The update card is more compact: "Update available — vX.Y.Z" with "Update via Homebrew · What's new" underneath. "Update via Homebrew" copies the upgrade command.

## [0.2.3] - 2026-09-25

### Fixed
- A speaker that reissued its TLS certificate (Sonos certificates last about six months) was rejected on every request since 0.2.1, so rooms it coordinated showed no music. The app now re-pins a changed key when the new certificate still names that speaker (its CN is the MAC inside the player ID); any other changed key is still rejected.

### Changed
- The copied upgrade command is now `brew update && brew upgrade --cask remote-for-sonos`, so it upgrades even when Homebrew's copy of the tap is a few hours stale (before, Homebrew could answer "already installed").

## [0.2.2] - 2026-09-12

### Added
- The panel tells you when a newer release exists: an "Update available" card with a copyable `brew upgrade --cask remote-for-sonos` command and a "What's new" link, dismissable per version; Settings shows the available version and has a "Check for updates" switch (on by default, one request to github.com a day).

## [0.2.1] - 2026-09-12

### Changed
- Speaker certificates are pinned on first contact and discovered addresses are validated; malformed network data no longer crashes the app.
- The panel keeps only household subscriptions while closed and no longer subscribes to per-player volume; the app re-renders only what changed.
- Every control is keyboard-focusable with Full Keyboard Access off; errors and connection changes are announced to VoiceOver; text and borders meet WCAG contrast; Reduce Motion is honoured.

## [0.2.0] - 2026-09-11

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

## [0.1.1] - 2026-09-10

### Changed
- The app is now called "Remote for Sonos" (display name and Settings window title); the bundle identifier and executable name are unchanged.
- Release builds are signed with Developer ID and use the hardened runtime; the version comes from `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`.
- Rows are ordered with playing (or buffering) groups first, then the rest, each tier alphabetical, so the room that is making sound is always at the top of the panel.

### Added
- `scripts/release.sh`: archive, sign, notarize, staple, zip, publish a GitHub Release, and update the Homebrew cask. Procedure in `knowledge/procedural/release.md`.
- Homebrew cask template (`packaging/remote-for-sonos.rb`) for `brew install --cask jens-wedin/tap/remote-for-sonos`.
- MIT `LICENSE`.

### Fixed
- "Settings…" did nothing visible: the Settings scene opened behind other windows from the Dock-less app. Settings is now a regular window that the app opens and brings to the front, returning to menu-bar-only mode when it closes.
- The play/pause button was invisible: its circle used a hierarchical fill that resolved to the glyph colour. Both now use explicit label and window-background colours.
- The PLAYING/PAUSED badge could wrap onto two lines in a closed row; it no longer wraps, and the closed-row slider is 130 pt wide to give the text room.
- The room list rendered with zero height inside the menu bar window (a `ScrollView` has no intrinsic size there), so the panel showed only the header and footer. The list now measures its rows and sizes itself to them, capped at 560 pt.

## [0.1.0] - 2026-09-05

### Added
- SonosKit package: Bonjour discovery, local API (REST + websocket) client, websocket event decoding, UPnP EQ client, and a `Household` actor that orchestrates discovery, sockets, subscriptions, and command dispatch with gateway failover and retry-with-backoff.
- sonosctl CLI for manual checks (list, play, pause, next, prev, volume, eq, watch).
- Menu bar app: group rows with live volume sliders, an open row with transport and per-speaker volume, favorites, EQ (including sub gain and loudness), grouping, status states ("Looking for Sonos…", "No Sonos found" with Retry), keyboard focus and VoiceOver support, and a Settings window with launch at login and a global panel shortcut.
- Stable manual code signing (Apple Development identity) so the Local Network permission grant survives rebuilds.

### Known gaps
- No "reconnecting" indicator on rows whose websocket is down; commands still work over REST while a socket reconnects.
