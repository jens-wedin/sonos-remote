# Changelog

All notable changes to this project are documented here. Format follows Keep a Changelog; versions follow SemVer.

## [Unreleased]

## [0.1.0] - 2026-09-05

### Added
- SonosKit package: Bonjour discovery, local API (REST + websocket) client, websocket event decoding, UPnP EQ client, and a `Household` actor that orchestrates discovery, sockets, subscriptions, and command dispatch with gateway failover and retry-with-backoff.
- sonosctl CLI for manual checks (list, play, pause, next, prev, volume, eq, watch).
- Menu bar app: group rows with live volume sliders, an open row with transport and per-speaker volume, favorites, EQ (including sub gain and loudness), grouping, status states ("Looking for Sonos…", "No Sonos found" with Retry), keyboard focus and VoiceOver support, and a Settings window with launch at login and a global panel shortcut.
- Stable manual code signing (Apple Development identity) so the Local Network permission grant survives rebuilds.
