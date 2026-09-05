# Build and run

Xcode 26 is installed but `xcode-select` points at the Command Line Tools. Export this in every shell:

    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

## Package

    cd Packages/SonosKit
    swift test                       # all tests
    swift test --filter ReducerTests # one suite
    swift run sonosctl list          # against the real speakers (Terminal needs Local Network permission)

## App

    xcodegen generate                # writes SonosRemote.xcodeproj (git-ignored)
    xcodebuild -project SonosRemote.xcodeproj -scheme SonosRemote -configuration Debug -derivedDataPath .build/xcode build 2>&1 | tail -3
    open .build/xcode/Build/Products/Debug/SonosRemote.app
    xcodebuild test -project SonosRemote.xcodeproj -scheme SonosRemote -destination 'platform=macOS' -derivedDataPath .build/xcode 2>&1 | tail -5

Quit a running copy before launching a new build: `pkill -x SonosRemote`.

### Signing (as of task 15b)

The app is signed with the Apple Development identity for team 4B85FPKBH8; the Local Network
grant survives rebuilds. `project.yml` sets `CODE_SIGN_STYLE: Automatic`,
`CODE_SIGN_IDENTITY: "Apple Development"`, `DEVELOPMENT_TEAM: 4B85FPKBH8` — no ad-hoc signature,
so macOS doesn't treat every rebuild as a new app and doesn't re-prompt for (or silently drop)
the Local Network permission.

If `xcodebuild build`/`test` complains it can't find a signing certificate or provisioning
profile, add `-allowProvisioningUpdates` to the command first. If it *still* fails with
`No Accounts: Add a new account in Accounts settings.`, Xcode has no Apple ID signed into its
Accounts preferences on that machine (and no cached provisioning profile), and automatic signing
cannot mint one non-interactively even though the certificate is present in the keychain — open
Xcode → Settings → Accounts and sign in with the `hello@jenswedin.com` Apple ID once, which lets
Xcode create/cache the Development profile; after that, headless `xcodebuild` builds should work.
Do not work around this by reverting to ad-hoc (`CODE_SIGN_IDENTITY: "-"`) — that reintroduces
the unstable-signature bug this fixed. `swift build`/`swift test` in `Packages/SonosKit` are
unaffected either way (the package doesn't sign anything).

To run the app's own unit tests without a working signing setup (e.g. to check the code compiles
and the logic tests pass while the account issue above is unresolved), disable signing for that
one invocation: `xcodebuild test ... CODE_SIGNING_ALLOWED=NO`. This is only useful as a
compile+logic smoke test — it does not produce a runnable, permission-stable `SonosRemote.app`
and doesn't substitute for the codesign/launch verification.

    codesign -dvv .build/xcode/Build/Products/Debug/SonosRemote.app 2>&1 | grep -E "TeamIdentifier|Authority"
    # expect: TeamIdentifier=4B85FPKBH8 and Authority=Apple Development: ...
