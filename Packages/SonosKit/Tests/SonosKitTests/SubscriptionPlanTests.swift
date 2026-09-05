import Foundation
import Testing
@testable import SonosKit

@Suite struct SubscriptionPlanTests {
    func snapshot() throws -> HouseholdSnapshot {
        let response = try JSONDecoder().decode(GroupsResponse.self, from: Fixtures.data("groups.json"))
        return SnapshotReducer.reduce(HouseholdSnapshot(), .topology(groups: response.groups, players: response.players))
    }

    @Test func coordinatorsGetGroupNamespacesMembersOnlyPlayerVolume() throws {
        let s = try snapshot()
        let plan = SubscriptionPlan.make(groups: s.groups, players: s.players, gatewayID: "RINCON_347E5C04E98101400")
        let gid = "RINCON_542A1B73A25001400:620674909"

        let flyttbar = try #require(plan["RINCON_542A1B73A25001400"])
        #expect(flyttbar == [
            Subscription(namespace: "playerVolume:1", scope: .player("RINCON_542A1B73A25001400")),
            Subscription(namespace: "playback:1", scope: .group(gid)),
            Subscription(namespace: "playbackMetadata:1", scope: .group(gid)),
            Subscription(namespace: "groupVolume:1", scope: .group(gid)),
        ])

        let stereo = try #require(plan["RINCON_347E5C04E98101400"])
        #expect(stereo == [
            Subscription(namespace: "playerVolume:1", scope: .player("RINCON_347E5C04E98101400")),
            Subscription(namespace: "groups:1", scope: .household),
            Subscription(namespace: "favorites:1", scope: .household),
        ])
        #expect(plan.count == 4)
    }

    @Test func missingGatewayFallsBackToFirstPlayerByID() throws {
        let s = try snapshot()
        let plan = SubscriptionPlan.make(groups: s.groups, players: s.players, gatewayID: nil)
        let household = plan.filter { $0.value.contains(Subscription(namespace: "groups:1", scope: .household)) }
        #expect(household.keys.first == "RINCON_347E5C04E98101400")
        #expect(household.count == 1)
    }
}
