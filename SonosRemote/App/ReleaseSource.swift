import Foundation

/// The one release the checker cares about: version without the `v`, the tag, and the release page.
struct ReleaseInfo: Hashable, Sendable {
    let version: String
    let tag: String
    let notesURL: URL

    init(version: String, tag: String, notesURL: URL) {
        self.version = version
        self.tag = tag
        self.notesURL = notesURL
    }

    /// Throws `.notStable` for drafts and pre-releases and `.unparsableTag` when the tag is not `vX.Y.Z`.
    init(wire: WireRelease) throws {
        guard !wire.draft, !wire.prerelease else { throw ReleaseSourceError.notStable(tag: wire.tagName) }
        guard SemanticVersion.parse(wire.tagName) != nil else { throw ReleaseSourceError.unparsableTag(wire.tagName) }
        let version = wire.tagName.hasPrefix("v") ? String(wire.tagName.dropFirst()) : wire.tagName
        self.init(version: version, tag: wire.tagName, notesURL: wire.htmlUrl)
    }
}

/// The fields of GitHub's `releases/latest` response this app reads. Decode with `.convertFromSnakeCase`.
struct WireRelease: Decodable, Sendable {
    let tagName: String
    let htmlUrl: URL
    let name: String?
    let body: String?
    let draft: Bool
    let prerelease: Bool
}

enum ReleaseSourceError: Error, Equatable {
    case http(Int)
    case notStable(tag: String)
    case unparsableTag(String)
}

protocol ReleaseSource: Sendable {
    func latest() async throws -> ReleaseInfo
}

/// Unauthenticated `GET releases/latest`. GitHub allows 60 such requests an hour per IP; this app makes one a day.
struct GitHubReleaseSource: ReleaseSource {
    static let endpoint = URL(string: "https://api.github.com/repos/jens-wedin/sonos-remote/releases/latest")!

    private let session: URLSession
    private let userAgentVersion: String

    init(session: URLSession = .shared, userAgentVersion: String) {
        self.session = session
        self.userAgentVersion = userAgentVersion
    }

    func makeRequest() -> URLRequest {
        var request = URLRequest(url: Self.endpoint, timeoutInterval: 8)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("RemoteForSonos/\(userAgentVersion)", forHTTPHeaderField: "User-Agent")
        return request
    }

    func latest() async throws -> ReleaseInfo {
        let (data, response) = try await session.data(for: makeRequest())
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ReleaseSourceError.http(http.statusCode)
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try ReleaseInfo(wire: try decoder.decode(WireRelease.self, from: data))
    }
}
