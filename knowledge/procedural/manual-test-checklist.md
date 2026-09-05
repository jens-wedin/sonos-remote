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
