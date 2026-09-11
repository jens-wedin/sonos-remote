# Session memory

Last state (2026-09-11, night): panel redesign round 1 is merged to `main` (PR #25) and RELEASED as v0.2.0 via `scripts/release.sh 0.2.0` (GitHub release + cask `jens-wedin/tap/remote-for-sonos` 0.2.0). Tests: package 79, app 41. Worktree and branch removed. Parked follow-ups: the Group screen's "playing elsewhere" hint is hidden from VoiceOver (fold it into the switch's accessibility label); a favorite's second line can repeat its kind. Round-2 candidates are listed in `docs/superpowers/specs/2026-09-11-panel-redesign-design.md`. `knowledge/design/sonos.pen` is an untracked Pencil file the owner added; decide whether to commit it.

Last state (2026-09-11): panel redesign round 1 is implemented on branch `sdd-panel-redesign` (ten tasks, all reviewed). The app suite has 34 tests and the package suite 79. The owner runs the manual checklist against the Debug build. After merge, `scripts/release.sh 0.2.0` cuts the release (requires the Unreleased notes moved under a `## [0.2.0] - <date>` heading first).

Last state (2026-09-10): v0.1.0 is merged on `main` and pushed; the app has been in daily use with post-merge fixes (list height, play button, badge, playing-first ordering, Settings window). Release tooling was added: `scripts/release.sh`, Developer ID Release signing in `project.yml`, a Homebrew cask template, `LICENSE`, and `knowledge/procedural/release.md`. The app was renamed to "Remote for Sonos" (display name only).

First public release shipped: v0.1.1 on 2026-09-10 via `scripts/release.sh 0.1.1` (Developer ID signed, notarized, stapled; GitHub Release + cask `jens-wedin/tap/remote-for-sonos`). One-time setup (Developer ID cert, `sonos-remote-notary` keychain profile, tap repo cloned to ~/Sandbox/Code/homebrew-tap) is done. Next release: move Unreleased notes under a version heading, commit, run `scripts/release.sh <version>`.

No app icon yet. The manual checklist has been exercised informally through daily use, not formally.

Next ideas (not started): app icon, media keys + Control Center now-playing, "show track in menu bar" option, AppKit panel shell for animated resize, Sparkle updates.
