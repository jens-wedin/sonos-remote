# GitHub Releases API (update check)

- Endpoint: `GET https://api.github.com/repos/jens-wedin/sonos-remote/releases/latest`, unauthenticated. Returns the newest release that is neither a draft nor a pre-release; 404 when the repository has no release.
- Headers sent: `Accept: application/vnd.github+json`, `User-Agent: RemoteForSonos/<version>` (GitHub rejects requests without a User-Agent with 403).
- Rate limit: 60 requests an hour per IP for unauthenticated calls (`X-RateLimit-Remaining` in the response). The app makes one a day: 30 s after launch, every 24 h, and on panel open when the last check is older than 24 h.
- Fields read: `tag_name` (`vX.Y.Z`, the release script's format), `html_url` (release page, used for "What's new"), `draft`, `prerelease`, `name`, `body`. Everything else is ignored. Fixture: `SonosRemoteTests/Fixtures/github-release-latest.json`, captured 2026-09-12 with `gh api repos/jens-wedin/sonos-remote/releases/latest`.
- Code: `SonosRemote/App/ReleaseSource.swift` (decoder, HTTP), `SonosRemote/App/UpdateChecker.swift` (policy; UserDefaults `updateCheckEnabled`, `dismissedUpdateVersion`, `lastUpdateCheck`), `SonosRemote/App/SemanticVersion.swift` (compare).
