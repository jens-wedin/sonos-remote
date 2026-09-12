import Foundation
import Testing
@testable import SonosKit

@Suite struct SubscriptionPlanTests {
    func snapshot() throws -> HouseholdSnapshot {
        let response = try JSONDecoder().decode(GroupsResponse.self, from: Fixtures.data("groups.json"))
        return SnapshotReducer.reduce(HouseholdSnapshot(), .topology(groups: response.groups, players: response.players))
    }

    @Test func coordinatorsGetGroupNamespacesWhilePanelIsOpenGatewayGetsHousehold() throws {
        let s = try snapshot()
        let plan = SubscriptionPlan.make(groups: s.groups, players: s.players, gatewayID: "RINCON_347E5C04E98101400", panelVisible: true)
        let gid = "RINCON_542A1B73A25001400:620674909"

        let flyttbar = try #require(plan["RINCON_542A1B73A25001400"])
        #expect(flyttbar == [
            Subscription(namespace: "playback:1", scope: .group(gid)),
            Subscription(namespace: "playbackMetadata:1", scope: .group(gid)),
            Subscription(namespace: "groupVolume:1", scope: .group(gid)),
        ])

        let stereo = try #require(plan["RINCON_347E5C04E98101400"])
        #expect(stereo == [
            Subscription(namespace: "groups:1", scope: .household),
            Subscription(namespace: "favorites:1", scope: .household),
        ])
        #expect(plan.count == 4)
        #expect(!plan.values.contains { $0.contains { $0.namespace == "playerVolume:1" } })
    }

    @Test func missingGatewayFallsBackToFirstPlayerByID() throws {
        let s = try snapshot()
        let plan = SubscriptionPlan.make(groups: s.groups, players: s.players, gatewayID: nil, panelVisible: false)
        let household = plan.filter { $0.value.contains(Subscription(namespace: "groups:1", scope: .household)) }
        #expect(household.keys.first == "RINCON_347E5C04E98101400")
        #expect(household.count == 1)
    }

    @Test func closedPanelKeepsOnlyHouseholdSubscriptions() {
        let player = Player(id: "P1", name: "Kitchen", address: "192.168.1.10", hasSub: false)
        let group = Group(id: "G1", name: "Kitchen", coordinatorID: "P1", playerIDs: ["P1"], playbackState: .idle, volume: .silent, nowPlaying: nil)
        let closed = SubscriptionPlan.make(groups: [group], players: [player], gatewayID: "P1", panelVisible: false)
        #expect(closed["P1"]?.map(\.namespace).sorted() == ["favorites:1", "groups:1"])
        let open = SubscriptionPlan.make(groups: [group], players: [player], gatewayID: "P1", panelVisible: true)
        #expect(open["P1"]?.map(\.namespace).sorted() == ["favorites:1", "groupVolume:1", "groups:1", "playback:1", "playbackMetadata:1"])
        #expect(!open.values.contains { $0.contains { $0.namespace == "playerVolume:1" } })
    }
}
