# Manual test checklist (run before tagging a version)

Preconditions: at least one room playing, one multi-room group, Terminal has Local Network permission.

1. Launch: icon in menu bar, no Dock icon, panel shows "Looking for Sonos…" then all groups within 5 s.
2. Main screen: the selected room's art, title, artist, album; progress bar advances once a second and the remaining time counts down; radio shows only the source line. Shuffle and repeat toggle and light up; the Sonos app agrees.
3. Rooms list: playing rooms first; clicking art or text selects (hero changes, row highlights); each row's slider moves its own group; change a volume in the Sonos app → the slider follows.
4. Favorites (heart): the picker starts on the selected room; search filters and the count updates; a station without artwork shows the radio glyph; clicking a row plays it on the chosen room.
5. Sound (sliders): the picker starts on the selected room's coordinator; values match `sonosctl eq <room>`; Warm lights at +3/−2, Custom otherwise; Reset zeroes bass, treble and sub; sub row only on the Amp; double-click resets one slider; loudness toggles.
6. Group: toggle a room on → joins within 2 s; toggle off → releases. Coordinator toggle disabled.
7. Keyboard: Escape closes from every screen; Cmd-[ returns to main; Up/Down move through rooms, Return selects, Space toggles play on the focused room; Tab reaches every control. VoiceOver reads the header as a header, each icon by screen name, the back button as "Back".
8. Errors: Wi‑Fi off at launch → "No Sonos found" + Retry works. Pull the plug on a speaker → its row disappears within 30 s.
9. Settings (gear): green dot + "Connected" + "<n> speakers · S2 · <version>"; refresh reruns discovery; launch at login registers; the shortcut records and opens the panel; the version matches the footer; Releases opens the browser. No Dock icon ever appears.
10. Quit from the footer.
11. Power off or disconnect every speaker (or the router): within ~30 s the panel shows "No Sonos found on this network" with Retry, not an empty list; power back on and Retry (or wait) → rows return.
12. Navigation: tapping the active icon returns to main; switching screens slides; the panel height follows the content and scrolls above 640 pt (a household with 10+ favorites).
13. Close the panel with music playing; within a few seconds Activity Monitor shows the app idle (no once-per-second CPU wakeups). Reopen: the progress bar resumes ticking.
14. Updates: build with `MARKETING_VERSION` set below the latest release (`xcodebuild … MARKETING_VERSION=0.0.1`); within 30 s of launch the main screen shows "Update available — v<latest>". "Update via Homebrew · What's new" sits under the title; "Update via Homebrew" swaps to "Copied" and pasting in Terminal gives `brew update && brew upgrade --cask remote-for-sonos`; "What's new" opens the release page; X hides the card and Settings → Version still says "Update available: <latest>" with the copy button. Switch "Check for updates" off → the card and the Settings line disappear; on again → they return. VoiceOver announces "Update available, version <latest>" once and reads the three buttons by name.
15. Untrusted speaker (covered by `TrustPolicyTests`/`HouseholdTests`; only check by hand when touching the banner): in a Debug build, temporarily make `TrustPolicy.playerID(_:matchesCommonName:)` return false and change one entry in the `speakerKeyPins` default. Expect a yellow "Can't verify <room>" banner and one VoiceOver announcement; revert and relaunch and it is gone.
