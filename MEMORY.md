# Session memory

Last state (2026-09-10): v0.1.0 is merged on `main` and pushed; the app has been in daily use with post-merge fixes (list height, play button, badge, playing-first ordering, Settings window). Release tooling was added: `scripts/release.sh`, Developer ID Release signing in `project.yml`, a Homebrew cask template, `LICENSE`, and `knowledge/procedural/release.md`. The app was renamed to "Remote for Sonos" (display name only).

Blocked on the owner's one-time steps before the first release: create the Developer ID Application certificate in Xcode, store notarization credentials under the keychain profile `sonos-remote-notary`, and create the `jens-wedin/homebrew-tap` repository. Then: move the Unreleased changelog notes under a new version heading, commit, and run `scripts/release.sh <version>`.

No app icon yet. The manual checklist has been exercised informally through daily use, not formally.

Next ideas (not started): app icon, media keys + Control Center now-playing, "show track in menu bar" option, AppKit panel shell for animated resize, Sparkle updates.
