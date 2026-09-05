import Foundation

/// REST calls to the local Control API on port 1443. Group-scoped calls must be sent to the
/// group's coordinator address; the caller (Household) is responsible for picking it.
public struct LocalAPIClient: Sendable {
    public static let apiKey = "123e4567-e89b-12d3-a456-426655440000"
    public static let port = 1443

    private let transport: any Transport

    public init(transport: any Transport) {
        self.transport = transport
    }

    // MARK: Reads

    func groups(from address: String) async throws -> GroupsResponse {
        try await get(GroupsResponse.self, address: address, path: "/households/local/groups")
    }

    public func favorites(from address: String) async throws -> [Favorite] {
        try await get(WireFavoritesList.self, address: address, path: "/households/local/favorites").items.map(Favorite.init(wire:))
    }

    // MARK: Group commands (send to the coordinator)

    public func play(groupID: String, at address: String) async throws {
        try await post(address: address, path: "/groups/\(groupID)/playback/play")
    }

    public func pause(groupID: String, at address: String) async throws {
        try await post(address: address, path: "/groups/\(groupID)/playback/pause")
    }

    public func next(groupID: String, at address: String) async throws {
        try await post(address: address, path: "/groups/\(groupID)/playback/skipToNextTrack")
    }

    public func previous(groupID: String, at address: String) async throws {
        try await post(address: address, path: "/groups/\(groupID)/playback/skipToPreviousTrack")
    }

    public func setGroupVolume(_ level: Int, groupID: String, at address: String) async throws {
        try await post(address: address, path: "/groups/\(groupID)/groupVolume", body: VolumeBody(volume: level))
    }

    public func setGroupMuted(_ muted: Bool, groupID: String, at address: String) async throws {
        try await post(address: address, path: "/groups/\(groupID)/groupVolume/mute", body: MutedBody(muted: muted))
    }

    public func loadFavorite(_ favoriteID: String, groupID: String, at address: String) async throws {
        try await post(address: address, path: "/groups/\(groupID)/favorites", body: FavoriteBody(favoriteId: favoriteID, playOnCompletion: true))
    }

    public func setGroupMembers(_ playerIDs: [String], groupID: String, at address: String) async throws {
        try await post(address: address, path: "/groups/\(groupID)/groups/setGroupMembers", body: MembersBody(playerIds: playerIDs))
    }

    // MARK: Player commands (send to that player)

    public func setPlayerVolume(_ level: Int, playerID: String, at address: String) async throws {
        try await post(address: address, path: "/players/\(playerID)/playerVolume", body: VolumeBody(volume: level))
    }

    public func setPlayerMuted(_ muted: Bool, playerID: String, at address: String) async throws {
        try await post(address: address, path: "/players/\(playerID)/playerVolume/mute", body: MutedBody(muted: muted))
    }

    // MARK: Plumbing

    private struct VolumeBody: Encodable { var volume: Int }
    private struct MutedBody: Encodable { var muted: Bool }
    private struct FavoriteBody: Encodable { var favoriteId: String; var playOnCompletion: Bool }
    private struct MembersBody: Encodable { var playerIds: [String] }

    func makeRequest(method: String, address: String, path: String, body: Data? = nil) -> APIRequest {
        var headers = ["X-Sonos-Api-Key": Self.apiKey]
        if body != nil { headers["Content-Type"] = "application/json" }
        guard let url = URL(string: "https://\(address):\(Self.port)/api/v1\(path)") else {
            preconditionFailure("Bad local API URL for \(address) \(path)")
        }
        return APIRequest(method: method, url: url, headers: headers, body: body)
    }

    private func perform(_ request: APIRequest) async throws -> Data {
        let response = try await transport.send(request)
        guard (200..<300).contains(response.status) else {
            throw LocalAPIError.from(status: response.status, body: response.body)
        }
        return response.body
    }

    private func get<T: Decodable>(_ type: T.Type, address: String, path: String) async throws -> T {
        let data = try await perform(makeRequest(method: "GET", address: address, path: path))
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw LocalAPIError.decoding("\(path): \(error)")
        }
    }

    private func post(address: String, path: String) async throws {
        _ = try await perform(makeRequest(method: "POST", address: address, path: path))
    }

    private func post<Body: Encodable>(address: String, path: String, body: Body) async throws {
        let data = try JSONEncoder().encode(body)
        _ = try await perform(makeRequest(method: "POST", address: address, path: path, body: data))
    }
}
