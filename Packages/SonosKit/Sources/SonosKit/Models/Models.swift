import Foundation

public enum PlaybackState: String, Sendable, Codable, Hashable {
    case playing = "PLAYBACK_STATE_PLAYING"
    case paused = "PLAYBACK_STATE_PAUSED"
    case idle = "PLAYBACK_STATE_IDLE"
    case buffering = "PLAYBACK_STATE_BUFFERING"

    /// Unknown wire values become `.idle` so a new firmware never crashes the app.
    public init(wireValue: String) {
        self = PlaybackState(rawValue: wireValue) ?? .idle
    }
}

public struct Volume: Hashable, Sendable {
    public var level: Int
    public var muted: Bool
    public var fixed: Bool

    public init(level: Int, muted: Bool, fixed: Bool) {
        self.level = level
        self.muted = muted
        self.fixed = fixed
    }

    public static let silent = Volume(level: 0, muted: false, fixed: false)
}

public struct NowPlaying: Hashable, Sendable {
    public var title: String
    public var artist: String?
    public var album: String?
    public var artworkURL: URL?
    public var serviceName: String?
    public var containerName: String?

    public init(title: String, artist: String? = nil, album: String? = nil, artworkURL: URL? = nil, serviceName: String? = nil, containerName: String? = nil) {
        self.title = title
        self.artist = artist
        self.album = album
        self.artworkURL = artworkURL
        self.serviceName = serviceName
        self.containerName = containerName
    }
}

public struct Player: Identifiable, Hashable, Sendable {
    public let id: String
    public var name: String
    /// IPv4 address the player answers on (ports 1443 and 1400).
    public var address: String
    public var hasSub: Bool

    public init(id: String, name: String, address: String, hasSub: Bool) {
        self.id = id
        self.name = name
        self.address = address
        self.hasSub = hasSub
    }
}

public struct Group: Identifiable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var coordinatorID: String
    public var playerIDs: [String]
    public var playbackState: PlaybackState
    public var volume: Volume
    public var nowPlaying: NowPlaying?

    public init(id: String, name: String, coordinatorID: String, playerIDs: [String], playbackState: PlaybackState, volume: Volume, nowPlaying: NowPlaying?) {
        self.id = id
        self.name = name
        self.coordinatorID = coordinatorID
        self.playerIDs = playerIDs
        self.playbackState = playbackState
        self.volume = volume
        self.nowPlaying = nowPlaying
    }
}

public struct Favorite: Identifiable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var subtitle: String?
    public var imageURL: URL?
    public var serviceName: String?

    public init(id: String, name: String, subtitle: String? = nil, imageURL: URL? = nil, serviceName: String? = nil) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.imageURL = imageURL
        self.serviceName = serviceName
    }
}

public struct EQSettings: Hashable, Sendable {
    public var bass: Int
    public var treble: Int
    public var loudness: Bool
    /// nil when the player has no sub.
    public var subGain: Int?

    public init(bass: Int, treble: Int, loudness: Bool, subGain: Int?) {
        self.bass = bass
        self.treble = treble
        self.loudness = loudness
        self.subGain = subGain
    }

    public static let bassRange = -10...10
    public static let trebleRange = -10...10
    public static let subGainRange = -15...15
}
