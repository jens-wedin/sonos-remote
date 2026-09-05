import Testing
@testable import SonosKit

@Suite struct FixturesTests {
    @Test func fixturesAreBundled() {
        #expect(Fixtures.data("groups.json").count > 1000)
        #expect(Fixtures.lines("events.jsonl").count == 13)
        #expect(Fixtures.string("soap_fault.xml").contains("<errorCode>402</errorCode>"))
        #expect(SonosKit.version == "0.1.0")
    }
}
