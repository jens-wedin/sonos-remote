#!/usr/bin/env bash
# Prints a one-item Sparkle appcast for a release.
#   scripts/make-appcast.sh <version> <build> <zip-url> <release-notes-url> <signature-attributes> [pub-date]
# <signature-attributes> is sign_update's output: sparkle:edSignature="…" length="…"
set -euo pipefail
[[ $# -ge 5 ]] || { sed -n '2,4p' "$0"; exit 2; }
VERSION="$1"; BUILD="$2"; ZIP_URL="$3"; NOTES_URL="$4"; SIG="$5"
PUB_DATE="${6:-$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')}"
[[ "$SIG" =~ ^sparkle:edSignature=\"[A-Za-z0-9+/=]+\"\ length=\"[0-9]+\"$ ]] || { echo "unexpected signature attributes: $SIG" >&2; exit 1; }
cat <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Remote for Sonos</title>
    <item>
      <title>Version $VERSION</title>
      <pubDate>$PUB_DATE</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>$NOTES_URL</sparkle:fullReleaseNotesLink>
      <enclosure url="$ZIP_URL" type="application/octet-stream" $SIG />
    </item>
  </channel>
</rss>
EOF
