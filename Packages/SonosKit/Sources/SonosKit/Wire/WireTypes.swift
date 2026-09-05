import Foundation

// Internal mirrors of the JSON the speakers send. Every field that Sonos may omit is optional.
// Unknown keys are ignored by JSONDecoder, which is what we want for forward compatibility.

struct WireObjectType: Decodable {
    var objectType: String
    enum CodingKeys: String, CodingKey { case objectType = "_objectType" }
}

struct GroupsResponse: Decodable, Sendable {
    var groups: [WireGroup]
    var players: [WirePlayer]
}

struct WireGroup: Decodable, Hashable, Sendable {
    var id: String
    var name: String
    var coordinatorId: String
    var playbackState: String?
    var playerIds: [String]
}

struct WirePlayer: Decodable, Hashable, Sendable {
    var id: String
    var name: String
    var websocketUrl: String

    static func host(fromWebsocketURL string: String) -> String? {
        URLComponents(string: string)?.host
    }
}

struct WireVolume: Decodable, Sendable {
    var volume: Int
    var muted: Bool
    var fixed: Bool
}

struct WirePlaybackStatus: Decodable, Sendable {
    var playbackState: String
}

struct WireService: Decodable, Sendable {
    var name: String?
}

struct WireNamed: Decodable, Sendable {
    var name: String?
}

struct WireTrack: Decodable, Sendable {
    var name: String?
    var imageUrl: String?
    var album: WireNamed?
    var artist: WireNamed?
    var service: WireService?
}

struct WireQueueItem: Decodable, Sendable {
    var track: WireTrack?
}

struct WireContainer: Decodable, Sendable {
    var name: String?
    var service: WireService?
}

struct WireMetadataStatus: Decodable, Sendable {
    var container: WireContainer?
    var currentItem: WireQueueItem?
}

struct WireFavorite: Decodable, Sendable {
    var id: String
    var name: String
    var description: String?
    var imageUrl: String?
    var service: WireService?
}

struct WireFavoritesList: Decodable, Sendable {
    var version: String?
    var items: [WireFavorite]
}

struct WireVersionChanged: Decodable, Sendable {
    var version: String?
}

struct WireGlobalError: Decodable, Sendable {
    var errorCode: String
    var reason: String?
}

struct WireCoordinatorChanged: Decodable, Sendable {
    var groupStatus: String
    var playerId: String?
    var websocketUrl: String?
}
