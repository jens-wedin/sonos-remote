# Session memory

Last state (2026-09-11): panel redesign round 1 is specced and planned, not yet implemented. Spec `docs/superpowers/specs/2026-09-11-panel-redesign-design.md` (approved; mockup `docs/design/2026-09-11-panel-mockup.png`), plan `docs/superpowers/plans/2026-09-11-panel-redesign.md` (10 tasks: SonosKit progress/play modes → app state → shell → main/favorites/sound/group/settings screens → docs). Linear project "Remote for Sonos" (team Studio Manfred) holds the spec document and issues STU-751..STU-760, one per task. Next: execute the plan (subagent-driven in a worktree), owner runs the manual checklist, then `scripts/release.sh 0.2.0`.

Last state (2026-09-10): v0.1.0 is merged on `main` and pushed; the app has been in daily use with post-merge fixes (list height, play button, badge, playing-first ordering, Settings window). Release tooling was added: `scripts/release.sh`, Developer ID Release signing in `project.yml`, a Homebrew cask template, `LICENSE`, and `knowledge/procedural/release.md`. The app was renamed to "Remote for Sonos" (display name only).

First public release shipped: v0.1.1 on 2026-09-10 via `scripts/release.sh 0.1.1` (Developer ID signed, notarized, stapled; GitHub Release + cask `jens-wedin/tap/remote-for-sonos`). One-time setup (Developer ID cert, `sonos-remote-notary` keychain profile, tap repo cloned to ~/Sandbox/Code/homebrew-tap) is done. Next release: move Unreleased notes under a version heading, commit, run `scripts/release.sh <version>`.

No app icon yet. The manual checklist has been exercised informally through daily use, not formally.

Next ideas (not started): app icon, media keys + Control Center now-playing, "show track in menu bar" option, AppKit panel shell for animated resize, Sparkle updates.
