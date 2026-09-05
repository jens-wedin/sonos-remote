# Changelog

All notable changes to this project are documented here. Format follows Keep a Changelog; versions follow SemVer.

## [Unreleased]

### Changed
- Rows are ordered with playing (or buffering) groups first, then the rest, each tier alphabetical, so the room that is making sound is always at the top of the panel.

### Fixed
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
