# Sparkle updates (in-app)

- Feed: `SUFeedURL` is `https://github.com/jens-wedin/sonos-remote/releases/latest/download/appcast.xml`. `appcast.xml` is uploaded as a release asset on every `gh release create`, so `releases/latest/download/appcast.xml` always resolves to the newest release's copy — no separate hosting, no branch to keep in sync.
- Sparkle decides what's newer by comparing `sparkle:version` (the appcast's `<sparkle:version>`, which is `CFBundleVersion` in the built app, which is the git commit count at release time — see `scripts/release.sh`'s `BUILD_NUMBER`) rather than the marketing `sparkle:shortVersionString`.
- The appcast uses `<sparkle:fullReleaseNotesLink>`, not `releaseNotesLink`: Sparkle hands that URL straight to the app's own "What's new" UI without fetching or rendering it itself. It points at the GitHub release page (`.../releases/tag/vX.Y.Z`).

## Keys

- Private EdDSA (ed25519) key lives in the owner's login Keychain, created once by `generate_keys` (Sparkle's `Sparkle/bin/generate_keys`), under the item "Private key for signing Sparkle updates". A backup lives in the password manager, exported with `generate_keys -x <file>`.
- Public key is `SUPublicEDKey` in `project.yml`: `pxnmYayx/gtqoXrOa6kIaUD3OOmVSgY1G7yZom65BD0=`. `generate_keys -p` prints exactly this value (nothing else) when the keychain already holds the matching private key — `scripts/release.sh` uses that to fail fast if the two ever disagree.
- Never run `generate_keys` without `-p`/`-x`/`-f` outside of the one-time setup: bare `generate_keys` will create a second key if none is found, which would silently orphan the one already embedded in shipped builds.

## Sandbox pieces the app needs (app stays sandboxed throughout)

- `SUEnableInstallerLauncherService: true`, `SUEnableAutomaticChecks: true`, `SUScheduledCheckInterval: 86400` in `project.yml`'s Info.plist block.
- Entitlements add exactly two mach-lookup exceptions: `$(PRODUCT_BUNDLE_IDENTIFIER)-spks` and `$(PRODUCT_BUNDLE_IDENTIFIER)-spki` (Sparkle's installer and installer-status XPC services).
- `Sparkle.framework`'s `Downloader.xpc` is stripped by the `Strip Sparkle Downloader service` post-build script in `project.yml` (only on `install`/archive actions, i.e. release builds) — the app already has network access itself, so Sparkle's own downloader XPC service is unused and would otherwise be one more sandboxed process to justify.
- `scripts/check-sparkle-config.sh <App.app> [--release]` asserts all of the above on a built app; `--release` additionally requires `Downloader.xpc` to be gone. `scripts/release.sh` runs it with `--release` right after codesign verification.

## Tools

Sparkle's CLI tools ship as build artifacts, not something installed separately:

    .build/xcode/SourcePackages/artifacts/sparkle/Sparkle/bin/        (Debug derived data)
    .build/xcode-release/SourcePackages/artifacts/sparkle/Sparkle/bin/ (Release derived data, used by scripts/release.sh)

`sign_update`, `generate_keys`, `generate_appcast`, `BinaryDelta` live there. `scripts/release.sh` calls `sign_update` (produces `sparkle:edSignature`/`length` for the appcast enclosure, then `--verify`s its own output) and `generate_keys -p` (key sanity check) rather than `generate_appcast`, since `scripts/make-appcast.sh` builds the one-item feed itself.

## Code

- `SonosRemote/App/UpdateController.swift` — the state machine (idle/checking/available/downloading/installing/error) that drives the update card.
- `SonosRemote/App/CardUserDriver.swift` — Sparkle's `SPUUserDriver`, translates Sparkle's callbacks into `UpdateController` state instead of showing Sparkle's own UI.
- `SonosRemote/App/SparkleUpdater.swift` — owns the `SPUUpdater`; nil under XCTest and when Sparkle fails to start (logged, card never appears).

## Debug-only launch arguments

- `-debugFeedURL <url>` — points the updater at a local feed instead of GitHub, e.g. `open "Remote for Sonos.app" --args -debugFeedURL http://localhost:8765/appcast.xml`. Read via `SparkleUpdater.feedURLString(for:)`, compiled out of Release.
- `-debugCheckNow` — set as a `UserDefaults` bool to trigger `checkForUpdatesInBackground()` immediately on launch instead of waiting for the scheduled interval. Also Debug-only.
