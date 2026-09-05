import Testing
import SonosKit
@testable import SonosRemote

@Suite struct RowOpenPolicyTests {
    func group(_ id: String, _ state: PlaybackState) -> Group {
        Group(id: id, name: id, coordinatorID: id, playerIDs: [id], playbackState: state, volume: .silent, nowPlaying: nil)
    }

    @Test func remembered_wins_when_it_exists() {
        let groups = [group("a", .idle), group("b", .playing)]
        #expect(RowOpenPolicy.resolve(remembered: "a", groups: groups) == "a")
    }

    @Test func first_playing_when_remembered_is_gone() {
        let groups = [group("a", .idle), group("b", .playing), group("c", .playing)]
        #expect(RowOpenPolicy.resolve(remembered: "zzz", groups: groups) == "b")
        #expect(RowOpenPolicy.resolve(remembered: nil, groups: groups) == "b")
    }

    @Test func first_group_when_nothing_plays() {
        let groups = [group("a", .idle), group("b", .paused)]
        #expect(RowOpenPolicy.resolve(remembered: nil, groups: groups) == "a")
    }

    @Test func nil_when_no_groups() {
        #expect(RowOpenPolicy.resolve(remembered: "a", groups: []) == nil)
    }
}
