import Foundation
import SonosKit

/// Pure helpers for the progress bar. Extrapolates from the last speaker report while playing.
enum PlaybackDisplay {
    static func displayedPosition(progress: PlaybackProgress, state: PlaybackState, now: Date) -> Int? {
        guard let duration = progress.durationMillis, duration > 0 else { return nil }
        var position = progress.positionMillis
        if state == .playing {
            let elapsed = now.timeIntervalSince(progress.reportedAt)
            if elapsed > 0 {
                let elapsedMillis = Int(min(elapsed, Double(PlaybackProgress.maximumMillis) / 1000) * 1000)
                let (sum, overflow) = position.addingReportingOverflow(elapsedMillis)
                position = overflow ? Int.max : sum
            }
        }
        return max(0, min(position, duration))
    }

    static func timeString(millis: Int) -> String {
        format(totalSeconds: max(0, millis / 1000))
    }

    /// Remaining time with a real minus sign, never below −0:00. Rounds up so the display never
    /// undercounts the time actually left (e.g. 187.5s remaining reads "3:08", not "3:07").
    static func remainingString(position: Int, duration: Int) -> String {
        let (difference, overflow) = duration.subtractingReportingOverflow(position)
        let remainingMillis = overflow ? (duration > position ? Int.max : 0) : max(0, difference)
        let totalSeconds = remainingMillis >= Int.max - 999 ? Int.max / 1000 : (remainingMillis + 999) / 1000
        return "−" + format(totalSeconds: totalSeconds)
    }

    private static func format(totalSeconds: Int) -> String {
        "\(totalSeconds / 60):" + String(format: "%02d", totalSeconds % 60)
    }

    /// Rooms list second line and the Group screen line: the track, the station for radio, or "Not playing".
    static func nowPlayingLine(for group: Group) -> String {
        guard group.playbackState != .idle, let now = group.nowPlaying else { return "Not playing" }
        if group.progress.durationMillis == nil, let container = now.containerName { return container }
        return now.title
    }

    /// "Spotify · Soft Evening Mix"; nil when the item names neither a service nor a container.
    static func sourceLine(for now: NowPlaying) -> String? {
        let parts = [now.serviceName, now.containerName].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
