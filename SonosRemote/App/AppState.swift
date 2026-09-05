import Foundation
import Observation
import SonosKit

@MainActor @Observable
final class AppState {
    private(set) var snapshot = HouseholdSnapshot()
    let household: Household
    private var consumeTask: Task<Void, Never>?

    init(household: Household) {
        self.household = household
    }

    static func live() -> AppState {
        let transport = URLSessionTransport()
        let household = Household(discovery: BonjourDiscovery(), transport: transport, trustStore: transport.trustStore)
        return AppState(household: household)
    }

    func start() {
        guard consumeTask == nil else { return }
        consumeTask = Task { [household] in
            await household.start()
            for await snapshot in await household.snapshots() {
                self.apply(snapshot)
            }
        }
    }

    func apply(_ snapshot: HouseholdSnapshot) {
        self.snapshot = snapshot
    }
}
