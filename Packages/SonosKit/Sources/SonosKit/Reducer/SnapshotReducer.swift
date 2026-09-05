import Foundation

enum SnapshotReducer {
    static func reduce(_ snapshot: HouseholdSnapshot, _ event: HouseholdEvent) -> HouseholdSnapshot {
        var next = snapshot
        switch event {
        case .status(let status):
            next.status = status

        case .topology(let wireGroups, let wirePlayers):
            let oldGroups = Dictionary(snapshot.groups.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let oldPlayers = Dictionary(snapshot.players.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            next.groups = wireGroups.map { wire in
                let old = oldGroups[wire.id]
                return Group(
                    id: wire.id,
                    name: wire.name,
                    coordinatorID: wire.coordinatorId,
                    playerIDs: wire.playerIds,
                    playbackState: wire.playbackState.map(PlaybackState.init(wireValue:)) ?? old?.playbackState ?? .idle,
                    volume: old?.volume ?? .silent,
                    nowPlaying: old?.nowPlaying
                )
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            next.players = wirePlayers
                .map { Player(wire: $0, hasSub: oldPlayers[$0.id]?.hasSub ?? false) }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        case .playbackStatus(let groupID, let state):
            update(&next, groupID) { $0.playbackState = state }

        case .metadata(let groupID, let nowPlaying):
            update(&next, groupID) { $0.nowPlaying = nowPlaying }

        case .groupVolume(let groupID, let volume):
            update(&next, groupID) { $0.volume = volume }

        case .playerVolume(let playerID, let volume):
            next.playerVolumes[playerID] = volume

        case .favorites(let favorites):
            next.favorites = favorites

        case .playerHasSub(let playerID, let hasSub):
            if let index = next.players.firstIndex(where: { $0.id == playerID }) {
                next.players[index].hasSub = hasSub
            }

        case .playerRemoved(let playerID):
            next.players.removeAll { $0.id == playerID }
            next.playerVolumes[playerID] = nil
            next.groups = next.groups.compactMap { group in
                var group = group
                group.playerIDs.removeAll { $0 == playerID }
                return group.playerIDs.isEmpty ? nil : group
            }
        }
        return next
    }

    private static func update(_ snapshot: inout HouseholdSnapshot, _ groupID: String, _ change: (inout Group) -> Void) {
        guard let index = snapshot.groups.firstIndex(where: { $0.id == groupID }) else { return }
        change(&snapshot.groups[index])
    }
}
