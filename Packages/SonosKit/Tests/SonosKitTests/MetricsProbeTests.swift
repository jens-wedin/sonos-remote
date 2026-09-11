import Foundation
import Synchronization
import Testing
@testable import SonosKit

/// Not behaviour tests: these print `METRIC id=value` lines that scripts/audit-metrics.py parses.
/// They never fail on the value; they only fail if the harness itself breaks.
@Suite struct MetricsProbeTests {
    /// How many snapshots the Household yields for 40 identical groupVolume events.
    /// Before the performance fixes every event yields (40 + the initial snapshot).
    @Test func snapshotYieldsPerBurst() async throws {
        let h = HouseholdTests.Harness()
        let first = try await h.startAndDiscover(DiscoveredPlayer(id: "RINCON_PROBE", address: "192.168.1.10", householdID: "hh"))
        let groupID = try #require(first.groups.first?.id)
        let socket = try #require(h.transport.sockets.first)

        let count = Mutex(0)
        let stream = await h.household.snapshots()
        let counter = Task {
            for await _ in stream { count.withLock { $0 += 1 } }
        }
        try await Task.sleep(for: .milliseconds(50))
        let frame = #"[{"namespace":"groupVolume:1","type":"groupVolume","groupId":"\#(groupID)"},{"volume":20,"muted":false,"fixed":false}]"#
        for _ in 0..<40 { socket.push(frame) }
        try await Task.sleep(for: .milliseconds(300))
        counter.cancel()
        let yields = count.withLock { $0 } - 1   // minus the initial snapshot every observer gets
        print("METRIC perf.snapshot_yields_per_40_burst=\(max(yields, 0))")
    }

    /// How many namespaces the coordinator's socket subscribes to when the panel is closed.
    @Test func subscriptionsWhileClosed() {
        let player = Player(id: "P1", name: "Kitchen", address: "192.168.1.10", hasSub: false)
        let group = Group(id: "G1", name: "Kitchen", coordinatorID: "P1", playerIDs: ["P1"], playbackState: .idle, volume: .silent, nowPlaying: nil)
        let plan = SubscriptionPlan.make(groups: [group], players: [player], gatewayID: "P1")
        let count = plan["P1"]?.count ?? 0
        let playerVolume = plan.values.contains { set in set.contains { $0.namespace == "playerVolume:1" } } ? 1 : 0
        print("METRIC perf.subscriptions_per_coordinator_closed=\(count)")
        print("METRIC perf.player_volume_subscribed=\(playerVolume)")
    }
}
