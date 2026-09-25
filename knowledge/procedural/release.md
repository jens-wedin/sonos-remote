# Releasing

Releases are built on the owner's Mac by `scripts/release.sh`, signed with a Developer ID certificate, notarized, and published as a GitHub Release plus a Homebrew cask in `jens-wedin/homebrew-tap`.

## One-time setup (done by the owner, needs the Apple Developer Program)

1. **Developer ID Application certificate.** Xcode → Settings → Accounts → add the Apple ID `hello@jenswedin.com` → select the team (FDBYWW84AR) → Manage Certificates → `+` → Developer ID Application. Only the account holder can create this. Verify:

       security find-identity -v -p codesigning | grep "Developer ID Application"

2. **Notarization credentials.** Create an app-specific password at account.apple.com → Sign-In and Security → App-Specific Passwords (name it `notarytool`). Then store it in the keychain under the profile the script expects:

       xcrun notarytool store-credentials sonos-remote-notary --apple-id hello@jenswedin.com --team-id FDBYWW84AR

   It prompts for the app-specific password. Verify with `xcrun notarytool history --keychain-profile sonos-remote-notary`.

3. **Homebrew tap.** Create the public repository once; the script clones it to `~/Sandbox/Code/homebrew-tap` (override with `TAP_DIR`):

       gh repo create jens-wedin/homebrew-tap --public --description "Homebrew tap for Jens Wedin's apps"

4. **Sparkle key (one time).** In-app updates are signed with an EdDSA (ed25519) key Sparkle manages in the Keychain; the script refuses to run without it.

       .build/xcode/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys

   Only run this bare (no flags) the very first time — it creates a new key in the owner's login Keychain (item "Private key for signing Sparkle updates") if one doesn't already exist, and prints the public key to put in `project.yml` as `SUPublicEDKey` (already done: `pxnmYayx/gtqoXrOa6kIaUD3OOmVSgY1G7yZom65BD0=`). Back it up once with:

       .build/xcode/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys -x ~/sparkle-private-key-backup.txt

   and store that file's contents in the password manager, then delete the local copy. Verify the keychain matches `project.yml` at any time with `generate_keys -p`, which should print exactly the `SUPublicEDKey` value.

   Only rotate this key while app builds are still signed with the same Developer ID certificate — a rotated key invalidates updates for everyone who hasn't yet received a build carrying the new public key, so a rotation needs a transition release that ships both.

## Cutting a release

1. Run the manual checklist (`manual-test-checklist.md`) on the current build.
2. In `changelog.md`, rename `## [Unreleased]` to `## [X.Y.Z] - YYYY-MM-DD` and add a fresh empty `## [Unreleased]` above it. Commit on `main` with a clean tree.
3. Run:

       scripts/release.sh X.Y.Z

   The script refuses to run on a dirty tree, an existing tag, a missing changelog section, missing credentials, or a missing/mismatched Sparkle key. Besides the app zip, it now signs the zip with the Sparkle key and writes `appcast.xml` (via `scripts/make-appcast.sh`) next to it. It writes everything under `.build/release/X.Y.Z/`, creates the `vX.Y.Z` tag through the GitHub Release, uploads both `Remote-for-Sonos-X.Y.Z.zip` and `appcast.xml`, and pushes the updated cask.
4. On another Mac: `brew install --cask jens-wedin/tap/remote-for-sonos`, launch, allow Local Network access, check that rooms appear.
5. See `knowledge/domain/sparkle-updates.md` for how the feed, keys, and sandbox pieces fit together, and for rehearsing an update against a local feed with `DOWNLOAD_BASE_URL` + `--skip-publish`.

Preflight treats untracked files as a dirty tree (`git status --porcelain`), so commit or locally exclude stray files (for example design files under `knowledge/design/`) before running the script.

## Rehearse before a release that changes updating

Any release that touches `UpdateController`, the Sparkle feed, the entitlements, or the signing/notarization steps in `scripts/release.sh` needs a rehearsal against that release's own build before it ships — not just the automated tests. Follow manual test checklist item 14 (`manual-test-checklist.md`): it builds the real, notarized release with a local feed, points a Debug copy at it, and walks the happy path, the failure-and-retry path, skip, and Settings' "Check now", so the one-click installer is proven end to end while it's still cheap to fix.

## Rehearsing without credentials

`scripts/release.sh X.Y.Z --skip-notarize --identity "Apple Development: hello@jenswedin.com (4B85FPKBH8)"` exercises archive, signing, and packaging with the development certificate and stops before notarization and publishing. Never distribute such a build.

## How the pieces fit

- `project.yml` has two signing configurations: Debug uses the Apple Development identity without the hardened runtime (so tests can inject into the app), Release uses `Developer ID Application` with the hardened runtime, which notarization requires. `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` feed the Info.plist; the script overrides them with the release version and the commit count.
- The archived product is `SonosRemote.app`; the script copies it to `Remote for Sonos.app` for distribution. The bundle id stays `com.jenswedin.SonosRemote` and the executable stays `SonosRemote`, so `pgrep -x SonosRemote` keeps working.
- Notarization is done on a zip of the app, then the ticket is stapled to the app and the final zip is rebuilt from the stapled app, so an offline first launch still passes Gatekeeper.
- `packaging/remote-for-sonos.rb` is the cask template; the script fills in version and sha256.
- Dependencies are pinned with `exactVersion` in project.yml; bump deliberately.

## Known gaps

- No app icon yet; the release shows the generic icon until one is added to an asset catalog and `project.yml`.
