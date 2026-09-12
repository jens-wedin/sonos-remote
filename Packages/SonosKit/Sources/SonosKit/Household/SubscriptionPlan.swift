import Foundation

/// Which websocket subscribes to what. Pure so it can be tested and diffed.
enum SubscriptionPlan {
    static let householdNamespaces = ["groups:1", "favorites:1"]
    static let groupNamespaces = ["playback:1", "playbackMetadata:1", "groupVolume:1"]

    /// Group (playback) namespaces are wanted only while the panel is visible — nothing
    /// renders them while it's closed. Household namespaces (topology, favorites) are always
    /// wanted so the panel opens with current state. `playerVolume:1` is never subscribed to:
    /// nothing in the app renders per-player volume from the socket (see perf audit H2); the
    /// `playerVolumes` snapshot field stays for `sonosctl` and simply remains empty.
    static func make(groups: [Group], players: [Player], gatewayID: String?, panelVisible: Bool) -> [String: Set<Subscription>] {
        var plan: [String: Set<Subscription>] = [:]
        if panelVisible {
            for group in groups {
                for namespace in groupNamespaces {
                    plan[group.coordinatorID, default: []].insert(Subscription(namespace: namespace, scope: .group(group.id)))
                }
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
