import Foundation

public enum HouseholdStatus: Sendable, Hashable {
    case discovering
    case ready
    case noPlayersFound
    case unauthorized
    case localNetworkDenied
}

public struct HouseholdSnapshot: Sendable, Hashable {
    public var status: HouseholdStatus
    public var groups: [Group]
    public var players: [Player]
    public var favorites: [Favorite]
    public var playerVolumes: [String: Volume]

    public init(status: HouseholdStatus = .discovering, groups: [Group] = [], players: [Player] = [], favorites: [Favorite] = [], playerVolumes: [String: Volume] = [:]) {
        self.status = status
        self.groups = groups
        self.players = players
        self.favorites = favorites
        self.playerVolumes = playerVolumes
    }

    public func group(_ id: String) -> Group? { groups.first { $0.id == id } }
    public func player(_ id: String) -> Player? { players.first { $0.id == id } }
    public func group(containing playerID: String) -> Group? { groups.first { $0.playerIDs.contains(playerID) } }
}
