import Testing
@testable import SonosRemote

@Suite struct SemanticVersionTests {
    @Test func parsesMajorMinorPatch() {
        let parsed = SemanticVersion.parse("0.2.1")
        #expect(parsed?.major == 0)
        #expect(parsed?.minor == 2)
        #expect(parsed?.patch == 1)
    }

    @Test func stripsLeadingVAndFillsMissingParts() {
        let parsed = SemanticVersion.parse("v1.0")
        #expect(parsed?.major == 1)
        #expect(parsed?.minor == 0)
        #expect(parsed?.patch == 0)
        #expect(SemanticVersion.parse("2")?.minor == 0)
    }

    @Test func rejectsPreReleaseSuffixAndGarbage() {
        #expect(SemanticVersion.parse("0.3.0-beta.1") == nil)
        #expect(SemanticVersion.parse("0.3.0rc1") == nil)
        #expect(SemanticVersion.parse("latest") == nil)
        #expect(SemanticVersion.parse("") == nil)
        #expect(SemanticVersion.parse("1.2.3.4") == nil)
        #expect(SemanticVersion.parse("1..3") == nil)
    }

    @Test func patchBumpIsNewer() {
        #expect(SemanticVersion.isNewer("0.2.2", than: "0.2.1"))
    }

    @Test func equalIsNotNewer() {
        #expect(!SemanticVersion.isNewer("0.2.1", than: "0.2.1"))
        #expect(!SemanticVersion.isNewer("v0.2.1", than: "0.2.1"))
    }

    @Test func olderIsNotNewer() {
        #expect(!SemanticVersion.isNewer("0.2.0", than: "0.2.1"))
        #expect(!SemanticVersion.isNewer("0.1.9", than: "0.2.0"))
    }

    @Test func minorBeatsPatchAndLeadingVIsIgnored() {
        #expect(SemanticVersion.isNewer("v0.3.0", than: "0.2.9"))
        #expect(SemanticVersion.isNewer("1.0", than: "0.9.9"))
    }

    @Test func preReleaseAndGarbageAreNeverNewer() {
        #expect(!SemanticVersion.isNewer("0.3.0-beta.1", than: "0.2.1"))
        #expect(!SemanticVersion.isNewer("latest", than: "0.2.1"))
        #expect(!SemanticVersion.isNewer("0.3.0", than: "dev"))
    }
}
