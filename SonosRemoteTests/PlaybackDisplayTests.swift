import Foundation
import Testing
import SonosKit
@testable import SonosRemote

@Suite struct PlaybackDisplayTests {
    let t0 = Date(timeIntervalSince1970: 1_000)

    func progress(position: Int, duration: Int? = 246_000) -> PlaybackProgress {
        PlaybackProgress(positionMillis: position, durationMillis: duration, reportedAt: t0, shuffle: false, repeatEnabled: false, canShuffle: true, canRepeat: true)
    }

    @Test func playingExtrapolatesFromReportTime() {
        let shown = PlaybackDisplay.displayedPosition(progress: progress(position: 100_000), state: .playing, now: t0.addingTimeInterval(2.5))
        #expect(shown == 102_500)
    }

    @Test func playingClampsToDuration() {
        let shown = PlaybackDisplay.displayedPosition(progress: progress(position: 245_000), state: .playing, now: t0.addingTimeInterval(10))
        #expect(shown == 246_000)
    }

    @Test func pausedFreezes() {
        let shown = PlaybackDisplay.displayedPosition(progress: progress(position: 100_000), state: .paused, now: t0.addingTimeInterval(30))
        #expect(shown == 100_000)
    }

    @Test func unknownDurationYieldsNil() {
        #expect(PlaybackDisplay.displayedPosition(progress: progress(position: 100_000, duration: nil), state: .playing, now: t0) == nil)
    }

    @Test func formatsTimes() {
        #expect(PlaybackDisplay.timeString(millis: 102_500) == "1:42")
        #expect(PlaybackDisplay.timeString(millis: 0) == "0:00")
        #expect(PlaybackDisplay.timeString(millis: 3_725_000) == "62:05")
        #expect(PlaybackDisplay.remainingString(position: 102_500, duration: 290_000) == "−3:08")
        #expect(PlaybackDisplay.remainingString(position: 300_000, duration: 290_000) == "−0:00")
    }

    @Test func nowPlayingLineUsesTitleContainerOrNotPlaying() {
        let now = NowPlaying(title: "Blue in Green", containerName: "P3")
        var group = Group(id: "g", name: "Kitchen", coordinatorID: "p", playerIDs: ["p"], playbackState: .playing, volume: .silent, nowPlaying: now, progress: progress(position: 0))
        #expect(PlaybackDisplay.nowPlayingLine(for: group) == "Blue in Green")
        group.progress = progress(position: 0, duration: nil)
        #expect(PlaybackDisplay.nowPlayingLine(for: group) == "P3", "radio shows the station (container) instead of the track")
        group.playbackState = .idle
        #expect(PlaybackDisplay.nowPlayingLine(for: group) == "Not playing")
    }

    @Test func sourceLineJoinsServiceAndContainer() {
        #expect(PlaybackDisplay.sourceLine(for: NowPlaying(title: "t", serviceName: "Spotify", containerName: "Soft Evening Mix")) == "Spotify · Soft Evening Mix")
        #expect(PlaybackDisplay.sourceLine(for: NowPlaying(title: "t", serviceName: "Spotify")) == "Spotify")
        #expect(PlaybackDisplay.sourceLine(for: NowPlaying(title: "t")) == nil)
    }
}
