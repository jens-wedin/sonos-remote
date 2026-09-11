import Foundation

/// Every fact that can change the household snapshot. Produced by REST results,
/// websocket events, discovery, and EQ probing. Consumed only by `SnapshotReducer`.
enum HouseholdEvent: Hashable, Sendable {
    case status(HouseholdStatus)
    case topology(groups: [WireGroup], players: [WirePlayer])
    case playbackStatus(groupID: String, state: PlaybackState, progress: PlaybackProgress)
    case metadata(groupID: String, nowPlaying: NowPlaying?, durationMillis: Int?)
    case groupVolume(groupID: String, volume: Volume)
    case playerVolume(playerID: String, volume: Volume)
    case favorites([Favorite])
    case playerHasSub(playerID: String, hasSub: Bool)
    case playerRemoved(playerID: String)
}
