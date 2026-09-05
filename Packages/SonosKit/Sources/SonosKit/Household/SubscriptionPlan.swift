import Foundation

/// Which websocket subscribes to what. Pure so it can be tested and diffed.
enum SubscriptionPlan {
    static let householdNamespaces = ["groups:1", "favorites:1"]
    static let groupNamespaces = ["playback:1", "playbackMetadata:1", "groupVolume:1"]

    static func make(groups: [Group], players: [Player], gatewayID: String?) -> [String: Set<Subscription>] {
        var plan: [String: Set<Subscription>] = [:]
        for player in players {
            plan[player.id] = [Subscription(namespace: "playerVolume:1", scope: .player(player.id))]
        }
        for group in groups {
            for namespace in groupNamespaces {
                plan[group.coordinatorID, default: []].insert(Subscription(namespace: namespace, scope: .group(group.id)))
            }
        }
        let gateway = players.first { $0.id == gatewayID }?.id ?? players.map(\.id).sorted().first
        if let gateway {
            for namespace in householdNamespaces {
                plan[gateway, default: []].insert(Subscription(namespace: namespace, scope: .household))
            }
        }
        return plan
    }
}
