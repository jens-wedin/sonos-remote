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

## Cutting a release

1. Run the manual checklist (`manual-test-checklist.md`) on the current build.
2. In `changelog.md`, rename `## [Unreleased]` to `## [X.Y.Z] - YYYY-MM-DD` and add a fresh empty `## [Unreleased]` above it. Commit on `main` with a clean tree.
3. Run:

       scripts/release.sh X.Y.Z

   The script refuses to run on a dirty tree, an existing tag, a missing changelog section, or missing credentials. It writes everything under `.build/release/X.Y.Z/`, creates the `vX.Y.Z` tag through the GitHub Release, uploads `Remote-for-Sonos-X.Y.Z.zip`, and pushes the updated cask.
4. On another Mac: `brew install --cask jens-wedin/tap/remote-for-sonos`, launch, allow Local Network access, check that rooms appear.

## Rehearsing without credentials

`scripts/release.sh X.Y.Z --skip-notarize --identity "Apple Development: hello@jenswedin.com (4B85FPKBH8)"` exercises archive, signing, and packaging with the development certificate and stops before notarization and publishing. Never distribute such a build.

## How the pieces fit

- `project.yml` has two signing configurations: Debug uses the Apple Development identity without the hardened runtime (so tests can inject into the app), Release uses `Developer ID Application` with the hardened runtime, which notarization requires. `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` feed the Info.plist; the script overrides them with the release version and the commit count.
- The archived product is `SonosRemote.app`; the script copies it to `Remote for Sonos.app` for distribution. The bundle id stays `com.jenswedin.SonosRemote` and the executable stays `SonosRemote`, so `pgrep -x SonosRemote` keeps working.
- Notarization is done on a zip of the app, then the ticket is stapled to the app and the final zip is rebuilt from the stapled app, so an offline first launch still passes Gatekeeper.
- `packaging/remote-for-sonos.rb` is the cask template; the script fills in version and sha256.

## Known gaps

- No app icon yet; the release shows the generic icon until one is added to an asset catalog and `project.yml`.
- No in-app updater; users update with `brew upgrade` or by downloading the next zip.
