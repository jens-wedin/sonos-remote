# Errors

Log format: date, what happened, deterministic or infrastructure, conclusion (if any).

| Date | Error | Kind | Conclusion |
|---|---|---|---|
| 2026-09-03 | Raw SSDP multicast from a shell process: `OSError: [Errno 65] No route to host` | Deterministic | macOS Local Network privacy blocks multicast for non-entitled processes. Use Bonjour (`NWBrowser`) instead. |
| 2026-09-05 | app stuck on discovering with no connections after rebuilds | Deterministic | ad-hoc signature changes per build, so macOS's Local Network grant no longer matched; fixed by signing with a stable Apple Development identity |
| 2026-09-05 | `xcodebuild ... -allowProvisioningUpdates` still fails: `error: No Accounts: Add a new account in Accounts settings.` / `error: No signing certificate "Mac Development" found: No "Mac Development" signing certificate matching team ID "4B85FPKBH8" with a private key was found.` | Infrastructure | This agent's environment has the `Apple Development: hello@jenswedin.com (4B85FPKBH8)` certificate in the login keychain (valid until 2027-01-31) but no Apple ID is signed into Xcode's Accounts preferences and no cached provisioning profile exists (`~/Library/Developer/Xcode/UserData/Provisioning Profiles/` empty, no `~/Library/MobileDevice/Provisioning Profiles/`), so Automatic signing cannot mint the Development profile the sandboxed app needs even with the cert present. Needs a human to open Xcode → Settings → Accounts and sign in once (or install a manually-generated matching profile) before `xcodebuild build`/`test` can produce a signed `SonosRemote.app` here; the package-level fix and its tests are unaffected. |
