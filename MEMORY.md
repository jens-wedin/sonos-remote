# Session memory

Last state (2026-09-12, evening): the update notice (daily GitHub release check, main-screen card with a copyable Homebrew command, Settings switch and Version row) is complete on branch `feat/update-notice` and open as PR #27 (https://github.com/jens-wedin/sonos-remote/pull/27), not merged. 77 app tests pass. Spec `docs/superpowers/specs/2026-09-12-update-notice-design.md`, plan `docs/superpowers/plans/2026-09-12-update-notice.md`. Next: merge the PR, run manual checklist item 14, move the changelog's Unreleased notes under `## [0.2.2] - <date>`, then `scripts/release.sh 0.2.2`. Later list: persist the last seen release across relaunch; Sparkle-style in-place updates.

Last state (2026-09-12): audit fix round 1 is complete on branch `audit-fixes-1` (worktree `.worktrees/audit-fixes-1`), Tasks 0–9 of `docs/superpowers/plans/2026-09-11-audit-fixes-round-1.md`, not yet merged. Before/after numbers live in `docs/audits/metrics/` (`before.json`, `after.json`, `history.md`) and the results report is `docs/audits/2026-09-11-fix-round-1.md`. Still open after this round: the a11y moderate/minor items (list semantics, dynamic type, truncation, screen-change announcements), the remaining performance mediums (artwork cache, EQ round trips, path monitoring) and security mediums (path escaping, artwork URL scheme, size caps), listed in the report. Next: final whole-branch review, owner's manual checks, merge, then a 0.2.1 release.

Last state (2026-09-11): panel redesign round 1 is implemented on branch `sdd-panel-redesign` (ten tasks, all reviewed). The app suite has 34 tests and the package suite 79. The owner runs the manual checklist against the Debug build. After merge, `scripts/release.sh 0.2.0` cuts the release (requires the Unreleased notes moved under a `## [0.2.0] - <date>` heading first).

Last state (2026-09-10): v0.1.0 is merged on `main` and pushed; the app has been in daily use with post-merge fixes (list height, play button, badge, playing-first ordering, Settings window). Release tooling was added: `scripts/release.sh`, Developer ID Release signing in `project.yml`, a Homebrew cask template, `LICENSE`, and `knowledge/procedural/release.md`. The app was renamed to "Remote for Sonos" (display name only).

First public release shipped: v0.1.1 on 2026-09-10 via `scripts/release.sh 0.1.1` (Developer ID signed, notarized, stapled; GitHub Release + cask `jens-wedin/tap/remote-for-sonos`). One-time setup (Developer ID cert, `sonos-remote-notary` keychain profile, tap repo cloned to ~/Sandbox/Code/homebrew-tap) is done. Next release: move Unreleased notes under a version heading, commit, run `scripts/release.sh <version>`.

No app icon yet. The manual checklist has been exercised informally through daily use, not formally.

Next ideas (not started): app icon, media keys + Control Center now-playing, "show track in menu bar" option, AppKit panel shell for animated resize, Sparkle updates.
