import Foundation
import Testing
@testable import SonosKit

@Suite struct LocalAPIClientTests {
    let transport = FakeTransport()
    var client: LocalAPIClient { LocalAPIClient(transport: transport) }
    let gid = "RINCON_542A1B73A25001400:620674909"

    @Test func getGroupsBuildsTheRightRequest() async throws {
        transport.respond(whenPathContains: "/households/local/groups", body: Fixtures.data("groups.json"))
        let response = try await client.groups(from: "192.168.1.105")
        #expect(response.groups.count == 3)
        let request = try #require(transport.requests.first)
        #expect(request.method == "GET")
        #expect(request.url.absoluteString == "https://192.168.1.105:1443/api/v1/households/local/groups")
        #expect(request.headers["X-Sonos-Api-Key"] == "123e4567-e89b-12d3-a456-426655440000")
        #expect(request.body == nil)
    }

    @Test func favoritesAreMapped() async throws {
        transport.respond(whenPathContains: "/favorites", body: Fixtures.data("favorites.json"))
        let favorites = try await client.favorites(from: "192.168.1.216")
        #expect(favorites.map(\.name) == ["P3"])
    }

    @Test func transportCommandsPostToCoordinatorPaths() async throws {
        try await client.play(groupID: gid, at: "192.168.1.216")
        try await client.pause(groupID: gid, at: "192.168.1.216")
        try await client.next(groupID: gid, at: "192.168.1.216")
        try await client.previous(groupID: gid, at: "192.168.1.216")
        let paths = transport.requests.map { $0.url.path }
        #expect(paths == [
            "/api/v1/groups/\(gid)/playback/play",
            "/api/v1/groups/\(gid)/playback/pause",
            "/api/v1/groups/\(gid)/playback/skipToNextTrack",
            "/api/v1/groups/\(gid)/playback/skipToPreviousTrack",
        ])
        #expect(transport.requests.allSatisfy { $0.method == "POST" })
    }

    @Test func volumeMuteFavoriteAndMembersSendJSONBodies() async throws {
        try await client.setGroupVolume(13, groupID: gid, at: "192.168.1.216")
        try await client.setGroupMuted(true, groupID: gid, at: "192.168.1.216")
        try await client.setPlayerVolume(20, playerID: "P1", at: "192.168.1.105")
        try await client.setPlayerMuted(false, playerID: "P1", at: "192.168.1.105")
        try await client.loadFavorite("3", groupID: gid, at: "192.168.1.216")
        try await client.setGroupMembers(["P1", "P2"], groupID: gid, at: "192.168.1.216")

        let requests = transport.requests
        #expect(requests.map { $0.url.path } == [
            "/api/v1/groups/\(gid)/groupVolume",
            "/api/v1/groups/\(gid)/groupVolume/mute",
            "/api/v1/players/P1/playerVolume",
            "/api/v1/players/P1/playerVolume/mute",
            "/api/v1/groups/\(gid)/favorites",
            "/api/v1/groups/\(gid)/groups/setGroupMembers",
        ])
        func json(_ i: Int) throws -> [String: Any] {
            let body = try #require(requests[i].body)
            return try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        }
        #expect(try json(0)["volume"] as? Int == 13)
        #expect(try json(1)["muted"] as? Bool == true)
        #expect(try json(2)["volume"] as? Int == 20)
        #expect(try json(3)["muted"] as? Bool == false)
        #expect(try json(4)["favoriteId"] as? String == "3")
        #expect(try json(4)["playOnCompletion"] as? Bool == true)
        #expect(try json(5)["playerIds"] as? [String] == ["P1", "P2"])
        #expect(requests.allSatisfy { $0.headers["Content-Type"] == "application/json" })
    }

    @Test func errorBodiesBecomeTypedErrors() {
        #expect(LocalAPIError.from(status: 400, body: Fixtures.data("error_400_nokey.json")) == .invalidAPIKey)
        #expect(LocalAPIError.from(status: 404, body: Fixtures.data("error_404_coordinator_moved.json")) == .coordinatorMoved(newCoordinatorID: "RINCON_542A1B73A25001400"))
        #expect(LocalAPIError.from(status: 404, body: Fixtures.data("error_unknown_group.json")) == .groupGone)
        let notAuthorized = Data(#"{"_objectType":"globalError","errorCode":"ERROR_NOT_AUTHORIZED"}"#.utf8)
        #expect(LocalAPIError.from(status: 401, body: notAuthorized) == .unauthorized)
        #expect(LocalAPIError.from(status: 401, body: Data()) == .unauthorized)
        #expect(LocalAPIError.from(status: 500, body: Data("oops".utf8)) == .http(status: 500))
    }

    @Test func nonSuccessResponsesThrow() async {
        transport.respond(whenPathContains: "/playback/play", status: 404, body: Fixtures.data("error_404_coordinator_moved.json"))
        await #expect(throws: LocalAPIError.coordinatorMoved(newCoordinatorID: "RINCON_542A1B73A25001400")) {
            try await client.play(groupID: gid, at: "192.168.1.105")
        }
    }

    @Test func undecodableBodyThrowsDecodingError() async {
        transport.respond(whenPathContains: "/groups", body: Data("<html>".utf8))
        await #expect(throws: LocalAPIError.self) {
            _ = try await client.groups(from: "192.168.1.105")
        }
    }
}
