import Foundation

/// The first element of every websocket frame the player sends or receives.
struct SocketHeader: Codable, Hashable, Sendable {
    var namespace: String
    var command: String?
    var response: String?
    var success: Bool?
    var type: String?
    var householdId: String?
    var groupId: String?
    var playerId: String?
}

/// A frame is `[header, body]`. Decoding is two-stage: header first, then the body by header type.
struct Frame<Body: Decodable>: Decodable {
    var header: SocketHeader
    var body: Body

    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        header = try container.decode(SocketHeader.self)
        body = try container.decode(Body.self)
    }
}

private struct HeaderOnly: Decodable {
    var header: SocketHeader
    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        header = try container.decode(SocketHeader.self)
    }
}

private struct EmptyBody: Codable {}

public struct Subscription: Hashable, Sendable {
    public enum Scope: Hashable, Sendable {
        case group(String)
        case player(String)
        case household
    }

    public var namespace: String
    public var scope: Scope

    public init(namespace: String, scope: Scope) {
        self.namespace = namespace
        self.scope = scope
    }

    /// `[{"namespace":…,"command":…,<scope key>:…},{}]`
    public func frame(command: String) -> Data {
        var header = SocketHeader(namespace: namespace, command: command)
        switch scope {
        case .group(let id): header.groupId = id
        case .player(let id): header.playerId = id
        case .household: header.householdId = "local"
        }
        let encoder = JSONEncoder()
        let headerData = try! encoder.encode(header)
        var data = Data("[".utf8)
        data.append(headerData)
        data.append(Data(",{}]".utf8))
        return data
    }
}

enum SocketEvent: Hashable, Sendable {
    case subscribed(namespace: String, success: Bool)
    case playbackStatus(groupID: String, state: PlaybackState)
    case metadata(groupID: String, nowPlaying: NowPlaying?)
    case groupVolume(groupID: String, volume: Volume)
    case playerVolume(playerID: String, volume: Volume)
    case groups(groups: [WireGroup], players: [WirePlayer])
    case favoritesChanged
    case globalError(code: String)
    case unknown(type: String)
}

enum SocketFrameDecoder {
    static func decode(_ data: Data) throws -> SocketEvent {
        let decoder = JSONDecoder()
        let header = try decoder.decode(HeaderOnly.self, from: data).header
        switch header.type {
        case "playbackStatus":
            let frame = try decoder.decode(Frame<WirePlaybackStatus>.self, from: data)
            return .playbackStatus(groupID: header.groupId ?? "", state: PlaybackState(wireValue: frame.body.playbackState))
        case "metadataStatus":
            let frame = try decoder.decode(Frame<WireMetadataStatus>.self, from: data)
            return .metadata(groupID: header.groupId ?? "", nowPlaying: NowPlaying(wire: frame.body))
        case "groupVolume":
            let frame = try decoder.decode(Frame<WireVolume>.self, from: data)
            return .groupVolume(groupID: header.groupId ?? "", volume: Volume(wire: frame.body))
        case "playerVolume":
            let frame = try decoder.decode(Frame<WireVolume>.self, from: data)
            return .playerVolume(playerID: header.playerId ?? "", volume: Volume(wire: frame.body))
        case "groups":
            let frame = try decoder.decode(Frame<GroupsResponse>.self, from: data)
            return .groups(groups: frame.body.groups, players: frame.body.players)
        case "versionChanged" where header.namespace.hasPrefix("favorites"):
            return .favoritesChanged
        case "globalError":
            let frame = try decoder.decode(Frame<WireGlobalError>.self, from: data)
            return .globalError(code: frame.body.errorCode)
        case "none", nil:
            if let response = header.response {
                _ = response
                return .subscribed(namespace: header.namespace, success: header.success ?? false)
            }
            return .unknown(type: header.type ?? "")
        default:
            return .unknown(type: header.type ?? "")
        }
    }
}
