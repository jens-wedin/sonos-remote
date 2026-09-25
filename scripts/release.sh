#!/usr/bin/env bash
# Build, sign, notarize, and publish a release of Remote for Sonos.
#
#   scripts/release.sh <version> [--skip-notarize] [--skip-publish] [--identity "<signing identity>"]
#
# Steps: preflight checks → xcodegen → xcodebuild archive (Release, Developer ID, hardened runtime)
# → codesign verification → notarize with notarytool → staple → Gatekeeper check → zip
# → GitHub Release (creates the v<version> tag) → update the Homebrew cask in jens-wedin/homebrew-tap.
# Every zip is also signed with the Sparkle EdDSA key and published with appcast.xml (the in-app update feed).
#
# One-time setup is documented in knowledge/procedural/release.md.
# --skip-notarize and --identity exist so the packaging flow can be rehearsed with the
# development certificate; never publish such a build.

set -euo pipefail

usage() { sed -n '2,13p' "$0"; exit 2; }

VERSION="${1:-}"; shift || true
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || usage

SKIP_NOTARIZE=0
SKIP_PUBLISH=0
IDENTITY="Developer ID Application"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-notarize) SKIP_NOTARIZE=1 ;;
    --skip-publish) SKIP_PUBLISH=1 ;;
    --identity) IDENTITY="$2"; shift ;;
    *) usage ;;
  esac
  shift
done

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

APP_NAME="Remote for Sonos"
PRODUCT="SonosRemote"
TAG="v$VERSION"
# Passed on the xcodebuild command line so Swift package resource bundles (KeyboardShortcuts)
# are signed with the same team; without it Xcode refuses to archive.
TEAM="${TEAM:-FDBYWW84AR}"
NOTARY_PROFILE="${NOTARY_PROFILE:-sonos-remote-notary}"
TAP_REPO="jens-wedin/homebrew-tap"
TAP_DIR="${TAP_DIR:-$HOME/Sandbox/Code/homebrew-tap}"
OUT="$REPO_ROOT/.build/release/$VERSION"
ARCHIVE="$OUT/$PRODUCT.xcarchive"
APP="$OUT/$APP_NAME.app"
ZIP="$OUT/Remote-for-Sonos-$VERSION.zip"
NOTES="$OUT/release-notes.md"
APPCAST="$OUT/appcast.xml"
SPARKLE_BIN="$REPO_ROOT/.build/xcode-release/SourcePackages/artifacts/sparkle/Sparkle/bin"
# Where the appcast says the zip lives; the rehearsal points it at a local server.
DOWNLOAD_BASE_URL="${DOWNLOAD_BASE_URL:-https://github.com/jens-wedin/sonos-remote/releases/download/$TAG}"
NOTES_URL="https://github.com/jens-wedin/sonos-remote/releases/tag/$TAG"

say() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
die() { printf '\n\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

say "Preflight"
[[ -z "$(git status --porcelain)" ]] || die "working tree is not clean; commit or stash first"
BRANCH="$(git branch --show-current)"
[[ "$BRANCH" == "main" ]] || echo "warning: releasing from branch '$BRANCH', not main"
if [[ $SKIP_PUBLISH -eq 0 ]]; then
  git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && die "tag $TAG already exists"
  gh auth status >/dev/null 2>&1 || die "gh is not authenticated"
fi
grep -q "^## \[$VERSION\]" changelog.md || die "changelog.md has no '## [$VERSION]' section; move the Unreleased notes there first"
security find-identity -v -p codesigning | grep -q "$IDENTITY" || die "no code-signing identity matching '$IDENTITY' in the keychain (see knowledge/procedural/release.md)"
if [[ $SKIP_NOTARIZE -eq 0 ]]; then
  xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 || die "no notarytool keychain profile '$NOTARY_PROFILE' (see knowledge/procedural/release.md)"
fi
command -v xcodegen >/dev/null || die "xcodegen is not installed (brew install xcodegen)"
command -v xmllint >/dev/null || die "xmllint is missing"

BUILD_NUMBER="$(git rev-list --count HEAD)"
echo "version $VERSION, build $BUILD_NUMBER, identity '$IDENTITY'"
rm -rf "$OUT"; mkdir -p "$OUT"

say "Release notes from changelog.md"
awk -v v="$VERSION" '
  $0 ~ "^## \\[" v "\\]" { inside = 1; next }
  inside && /^## \[/ { exit }
  inside { print }
' changelog.md | sed -e '1{/^$/d;}' > "$NOTES"
[[ -s "$NOTES" ]] || die "the changelog section for $VERSION is empty"
cat "$NOTES"

say "Generate project and check the Sparkle key"
xcodegen generate >/dev/null
xcodebuild -resolvePackageDependencies -project "$PRODUCT.xcodeproj" -scheme "$PRODUCT" -derivedDataPath "$REPO_ROOT/.build/xcode-release" -quiet
[[ -x "$SPARKLE_BIN/sign_update" ]] || die "Sparkle tools not found at $SPARKLE_BIN"
KEYCHAIN_KEY="$("$SPARKLE_BIN/generate_keys" -p 2>/dev/null)" || die "no Sparkle signing key in the keychain (see knowledge/procedural/release.md)"
grep -q "SUPublicEDKey: $KEYCHAIN_KEY" project.yml || die "the keychain's Sparkle key does not match SUPublicEDKey in project.yml"

say "Archive (Release)"
xcodebuild archive \
  -project "$PRODUCT.xcodeproj" -scheme "$PRODUCT" -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE" -derivedDataPath "$REPO_ROOT/.build/xcode-release" \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  CODE_SIGN_IDENTITY="$IDENTITY" DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Manual \
  -quiet
cp -R "$ARCHIVE/Products/Applications/$PRODUCT.app" "$APP"

say "Verify signature"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dvv "$APP" 2>&1 | grep -E "^Authority=|TeamIdentifier|Runtime Version" | head -4
plutil -p "$APP/Contents/Info.plist" | grep -E "CFBundleShortVersionString|CFBundleVersion\""
scripts/check-sparkle-config.sh "$APP" --release

if [[ $SKIP_NOTARIZE -eq 0 ]]; then
  say "Notarize"
  ditto -c -k --keepParent "$APP" "$OUT/notarize.zip"
  xcrun notarytool submit "$OUT/notarize.zip" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json > "$OUT/notarize.json" || true
  STATUS="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("status","?"))' "$OUT/notarize.json")"
  if [[ "$STATUS" != "Accepted" ]]; then
    ID="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("id",""))' "$OUT/notarize.json")"
    [[ -n "$ID" ]] && xcrun notarytool log "$ID" --keychain-profile "$NOTARY_PROFILE" || true
    die "notarization status: $STATUS"
  fi
  say "Staple and check Gatekeeper"
  xcrun stapler staple "$APP" >/dev/null
  xcrun stapler validate "$APP" >/dev/null
  spctl -a -vv -t exec "$APP" 2>&1 | grep -E "accepted|rejected"
else
  echo "skipping notarization (rehearsal build; do not distribute)"
fi

say "Package"
ditto -c -k --keepParent "$APP" "$ZIP"
SHA256="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
echo "$ZIP"
echo "sha256 $SHA256"

say "Sign the update and write the appcast"
SIG_ATTRS="$("$SPARKLE_BIN/sign_update" "$ZIP")"
SIGNATURE="$(sed -E 's/.*sparkle:edSignature="([^"]+)".*/\1/' <<<"$SIG_ATTRS")"
"$SPARKLE_BIN/sign_update" --verify "$ZIP" "$SIGNATURE" >/dev/null || die "sign_update could not verify the signature it just made"
scripts/make-appcast.sh "$VERSION" "$BUILD_NUMBER" "$DOWNLOAD_BASE_URL/Remote-for-Sonos-$VERSION.zip" "$NOTES_URL" "$SIG_ATTRS" > "$APPCAST"
xmllint --noout "$APPCAST"
echo "$APPCAST"

if [[ $SKIP_PUBLISH -eq 1 || $SKIP_NOTARIZE -eq 1 ]]; then
  say "Done (not published)"
  exit 0
fi

[[ "$DOWNLOAD_BASE_URL" == "https://github.com/jens-wedin/sonos-remote/releases/download/$TAG" ]] || die "DOWNLOAD_BASE_URL is overridden; only rehearsals (--skip-publish) may do that"

say "GitHub release $TAG"
gh release create "$TAG" "$ZIP" "$APPCAST" --title "$APP_NAME $VERSION" --notes-file "$NOTES" --target "$(git rev-parse HEAD)"
git fetch -q --tags origin

say "Homebrew cask"
if [[ ! -d "$TAP_DIR/.git" ]]; then
  gh repo view "$TAP_REPO" >/dev/null 2>&1 || die "tap repository $TAP_REPO does not exist; create it with: gh repo create $TAP_REPO --public"
  gh repo clone "$TAP_REPO" "$TAP_DIR" >/dev/null
fi
mkdir -p "$TAP_DIR/Casks"
# A freshly created tap repository is empty: make sure we are on main and set the upstream on first push.
git -C "$TAP_DIR" rev-parse -q --verify HEAD >/dev/null 2>&1 || git -C "$TAP_DIR" checkout -q -B main
sed -e "s/__VERSION__/$VERSION/" -e "s/__SHA256__/$SHA256/" packaging/remote-for-sonos.rb > "$TAP_DIR/Casks/remote-for-sonos.rb"
git -C "$TAP_DIR" add Casks/remote-for-sonos.rb
git -C "$TAP_DIR" commit -q -m "remote-for-sonos $VERSION" || echo "cask unchanged"
git -C "$TAP_DIR" push -q -u origin HEAD
echo "install with: brew install --cask jens-wedin/tap/remote-for-sonos"

say "Released $APP_NAME $VERSION"
