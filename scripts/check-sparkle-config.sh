#!/usr/bin/env bash
# Checks that a built Remote for Sonos.app carries the Sparkle configuration a sandboxed app needs.
#   scripts/check-sparkle-config.sh <path/to/App.app> [--release]
# --release also requires the Downloader XPC service to be stripped (archive builds only).
set -euo pipefail
APP="${1:?usage: scripts/check-sparkle-config.sh <App.app> [--release]}"
RELEASE="${2:-}"
fail() { echo "sparkle config: $*" >&2; exit 1; }
PLIST="$APP/Contents/Info.plist"
[[ "$(plutil -extract SUFeedURL raw "$PLIST" 2>/dev/null)" == "https://github.com/jens-wedin/sonos-remote/releases/latest/download/appcast.xml" ]] || fail "SUFeedURL missing or wrong"
[[ -n "$(plutil -extract SUPublicEDKey raw "$PLIST" 2>/dev/null)" ]] || fail "SUPublicEDKey missing"
[[ "$(plutil -extract SUEnableInstallerLauncherService raw "$PLIST" 2>/dev/null)" == "true" ]] || fail "SUEnableInstallerLauncherService is not true"
ENT="$(codesign -d --entitlements - --xml "$APP" 2>/dev/null)"
grep -q "com.jenswedin.SonosRemote-spks" <<<"$ENT" || fail "mach-lookup exception -spks missing"
grep -q "com.jenswedin.SonosRemote-spki" <<<"$ENT" || fail "mach-lookup exception -spki missing"
FW="$APP/Contents/Frameworks/Sparkle.framework"
[[ -d "$FW" ]] || fail "Sparkle.framework is not embedded"
[[ -d "$FW/Versions/B/XPCServices/Installer.xpc" ]] || fail "Installer.xpc missing"
if [[ "$RELEASE" == "--release" ]]; then
  [[ ! -e "$FW/Versions/B/XPCServices/Downloader.xpc" ]] || fail "Downloader.xpc must be stripped from release builds"
  # Xcode's "Code Sign on Copy" only re-signs Sparkle.framework itself on archive builds; its nested
  # helpers ship ad-hoc signed and must be re-signed by hand with the Developer ID identity and a
  # secure timestamp (project.yml's postBuildScripts), or Apple's notarization service rejects them.
  check_helper_signed() {
    local helper="$1" label="$2"
    [[ -e "$helper" ]] || fail "$label missing"
    local info; info="$(codesign -dvv "$helper" 2>&1)"
    grep -q "^Authority=Developer ID Application" <<<"$info" || fail "$label is not signed with a Developer ID Application certificate"
    grep -q "^Timestamp=" <<<"$info" || fail "$label signature is missing a secure timestamp"
  }
  check_helper_signed "$FW/Versions/B/XPCServices/Installer.xpc" "Installer.xpc"
  check_helper_signed "$FW/Versions/B/Autoupdate" "Autoupdate"
  check_helper_signed "$FW/Versions/B/Updater.app" "Updater.app"
fi
echo "sparkle config: ok"
