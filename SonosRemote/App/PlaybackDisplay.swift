import Foundation
import SonosKit

/// Pure helpers for the progress bar. Extrapolates from the last speaker report while playing.
enum PlaybackDisplay {
    static func displayedPosition(progress: PlaybackProgress, state: PlaybackState, now: Date) -> Int? {
        guard let duration = progress.durationMillis, duration > 0 else { return nil }
        var position = progress.positionMillis
        if state == .playing {
            let elapsed = now.timeIntervalSince(progress.reportedAt)
            if elapsed > 0 { position += Int(elapsed * 1000) }
        }
        return max(0, min(position, duration))
    }

    static func timeString(millis: Int) -> String {
        format(totalSeconds: max(0, millis / 1000))
    }

    /// Remaining time with a real minus sign, never below −0:00. Rounds up so the display never
    /// undercounts the time actually left (e.g. 187.5s remaining reads "3:08", not "3:07").
    static func remainingString(position: Int, duration: Int) -> String {
        let remainingMillis = max(0, duration - position)
        let totalSeconds = (remainingMillis + 999) / 1000
        return "−" + format(totalSeconds: totalSeconds)
    }

    private static func format(totalSeconds: Int) -> String {
        "\(totalSeconds / 60):" + String(format: "%02d", totalSeconds % 60)
    }
}
