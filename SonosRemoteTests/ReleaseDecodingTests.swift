import Foundation
import Testing
@testable import SonosRemote

/// Anchor for `Bundle(for:)`; Swift Testing suites are structs, so a class is needed to find the test bundle.
private final class FixtureAnchor {}

@Suite struct ReleaseDecodingTests {
    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle(for: FixtureAnchor.self).url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }

    private func decode(_ data: Data) throws -> WireRelease {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(WireRelease.self, from: data)
    }

    @Test func decodesTheCapturedLatestRelease() throws {
        let wire = try decode(try fixture("github-release-latest"))
        #expect(wire.tagName == "v0.2.1")
        #expect(wire.htmlUrl.absoluteString == "https://github.com/jens-wedin/sonos-remote/releases/tag/v0.2.1")
        #expect(wire.name == "Remote for Sonos 0.2.1")
        #expect(wire.draft == false)
        #expect(wire.prerelease == false)
        #expect(wire.body?.isEmpty == false)
    }

    @Test func convertsToReleaseInfoWithoutTheV() throws {
        let info = try ReleaseInfo(wire: try decode(try fixture("github-release-latest")))
        #expect(info == ReleaseInfo(
            version: "0.2.1",
            tag: "v0.2.1",
            notesURL: URL(string: "https://github.com/jens-wedin/sonos-remote/releases/tag/v0.2.1")!
        ))
    }

    @Test func decodesMinimalJSONWithMissingOptionals() throws {
        let json = #"{"tag_name":"v0.3.0","html_url":"https://example.com/r/v0.3.0","draft":false,"prerelease":false}"#
        let info = try ReleaseInfo(wire: try decode(Data(json.utf8)))
        #expect(info.version == "0.3.0")
        #expect(info.tag == "v0.3.0")
    }

    @Test func preReleaseAndDraftThrowNotStable() throws {
        let pre = #"{"tag_name":"v0.3.0","html_url":"https://example.com/r","draft":false,"prerelease":true}"#
        let draft = #"{"tag_name":"v0.3.0","html_url":"https://example.com/r","draft":true,"prerelease":false}"#
        #expect(throws: ReleaseSourceError.notStable(tag: "v0.3.0")) {
            try ReleaseInfo(wire: try decode(Data(pre.utf8)))
        }
        #expect(throws: ReleaseSourceError.notStable(tag: "v0.3.0")) {
            try ReleaseInfo(wire: try decode(Data(draft.utf8)))
        }
    }

    @Test func unparsableTagThrows() throws {
        let json = #"{"tag_name":"nightly","html_url":"https://example.com/r","draft":false,"prerelease":false}"#
        #expect(throws: ReleaseSourceError.unparsableTag("nightly")) {
            try ReleaseInfo(wire: try decode(Data(json.utf8)))
        }
    }

    @Test func endpointAndHeadersAreFixed() {
        #expect(GitHubReleaseSource.endpoint.absoluteString == "https://api.github.com/repos/jens-wedin/sonos-remote/releases/latest")
        let request = GitHubReleaseSource(userAgentVersion: "0.2.1").makeRequest()
        #expect(request.url == GitHubReleaseSource.endpoint)
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "RemoteForSonos/0.2.1")
        #expect(request.timeoutInterval == 8)
    }
}
