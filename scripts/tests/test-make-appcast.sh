#!/usr/bin/env bash
# Tests scripts/make-appcast.sh: valid XML, every field in place, bad signatures refused.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
SIG='sparkle:edSignature="abc+/def=" length="4242"'
OUT="$(scripts/make-appcast.sh 0.2.5 123 https://example.com/Remote-for-Sonos-0.2.5.zip https://example.com/releases/tag/v0.2.5 "$SIG" 'Thu, 25 Sep 2026 10:00:00 +0000')"
xmllint --noout - <<<"$OUT"
grep -q '<sparkle:version>123</sparkle:version>' <<<"$OUT"
grep -q '<sparkle:shortVersionString>0.2.5</sparkle:shortVersionString>' <<<"$OUT"
grep -q '<sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>' <<<"$OUT"
grep -q '<sparkle:fullReleaseNotesLink>https://example.com/releases/tag/v0.2.5</sparkle:fullReleaseNotesLink>' <<<"$OUT"
grep -q '<pubDate>Thu, 25 Sep 2026 10:00:00 +0000</pubDate>' <<<"$OUT"
grep -q 'url="https://example.com/Remote-for-Sonos-0.2.5.zip" type="application/octet-stream" sparkle:edSignature="abc+/def=" length="4242"' <<<"$OUT"
if scripts/make-appcast.sh 0.2.5 123 u n 'garbage' >/dev/null 2>&1; then echo "FAIL: accepted a malformed signature"; exit 1; fi
echo "make-appcast: ok"
