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

The app is signed **manually** with the owner's Apple Development identity; the Local Network
grant survives rebuilds because the signature is now real (not ad-hoc) and stable across builds.
`project.yml` sets:

    CODE_SIGN_STYLE: Manual
    CODE_SIGN_IDENTITY: "Apple Development: hello@jenswedin.com (4B85FPKBH8)"
    DEVELOPMENT_TEAM: FDBYWW84AR
    PROVISIONING_PROFILE_SPECIFIER: ""

**Team ID gotcha:** the string in parentheses in the certificate's display name/CN —
`(4B85FPKBH8)` — is the developer's personal ID, *not* the team ID. The real team ID is the
certificate's OU field, which for this identity is `FDBYWW84AR` (confirm with
`security find-certificate -a -c "Apple Development" -p ~/Library/Keychains/login.keychain-db |
openssl x509 -noout -subject`, or after a successful build,
`codesign -dvv .../SonosRemote.app | grep TeamIdentifier`). Using the parenthetical value as
`DEVELOPMENT_TEAM` makes even Manual signing fail (`No certificate for team '4B85FPKBH8' matching
...`); using the real OU value works.

Manual signing with an explicit `CODE_SIGN_IDENTITY` + `DEVELOPMENT_TEAM` needs **no Xcode
account and no provisioning profile** for this app (sandboxed, only the network-client
entitlement) — `PROVISIONING_PROFILE_SPECIFIER: ""` tells Xcode not to look for one. This is
the preferred path in headless/CI-like environments (no interactive Xcode session to sign into
an Apple ID). Do not fall back to `CODE_SIGN_STYLE: Automatic` here unless an Apple ID is
already signed into Xcode's Accounts preferences on the machine (`-allowProvisioningUpdates`
alone isn't enough — it fails with `No Accounts: Add a new account in Accounts settings.` if
none is signed in) and never revert to ad-hoc (`CODE_SIGN_IDENTITY: "-"`) — that reintroduces
the unstable-signature bug this fixed. `swift build`/`swift test` in `Packages/SonosKit` are
unaffected either way (the package doesn't sign anything).

    xcodebuild -project SonosRemote.xcodeproj -scheme SonosRemote -configuration Debug -derivedDataPath .build/xcode build 2>&1 | grep -E "error:|warning: .*Swift|BUILD"
    codesign -dvv .build/xcode/Build/Products/Debug/SonosRemote.app 2>&1 | grep -E "TeamIdentifier|Authority"
    # expect: TeamIdentifier=FDBYWW84AR and Authority=Apple Development: hello@jenswedin.com (4B85FPKBH8)

`xcodebuild test` against the signed app occasionally hangs on its first invocation right after a
fresh signed build ("the test runner hung before establishing connection" / `TEST FAILED` after
~5–6 minutes) — a known flaky interaction between a freshly-signed sandboxed `LSUIElement` test
host and the test runner launch handshake, not a code or signing problem. Simply retrying the
same `xcodebuild test` command succeeds. If it keeps hanging, retry once more with
`-only-testing:SonosRemoteTests` under a `timeout 300 xcodebuild test …` cap; only if that also
hangs, fall back to `xcodebuild test ... CODE_SIGNING_ALLOWED=NO` as a compile+logic smoke test
(it does not produce a runnable, permission-stable `SonosRemote.app` and doesn't substitute for
the codesign/launch verification below).

`log show --predicate 'subsystem == "com.jenswedin.SonosRemote"'` after the fact only shows
`.error`/`.fault`-level lines from our `os.Logger` calls (and `.notice`, unused here) — `.info`
lines (most of what task 15b added) are not persisted to the unified-log store by default and
won't appear in a retroactive `log show`, even though the app definitely emitted them. To see
`.info` lines, stream live instead, started *before* launching/reproducing:

    /usr/bin/log stream --style compact --level info --predicate 'subsystem == "com.jenswedin.SonosRemote"'

(Use the full path `/usr/bin/log` — plain `log` in this zsh setup resolves to a shell builtin
that isn't the unified-logging tool and fails with `too many arguments`.)
