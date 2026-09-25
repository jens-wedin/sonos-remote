import Testing
@testable import SonosRemote

@MainActor
@Suite struct SparkleUpdaterTests {
    @Test func sparkleNeverStartsInsideTheTestHost() {
        #expect(SparkleUpdater(controller: UpdateController()) == nil, "test runs must never reach the update feed")
    }
}
