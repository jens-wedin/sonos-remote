import SwiftUI
import SonosKit

/// 3 pt bar with elapsed, source and remaining; hidden (source only) when the duration is unknown.
struct ProgressBarView: View {
    @Environment(AppState.self) private var state
    let group: SonosGroup

    var body: some View {
        // Reading `tick` re-renders once a second while the room plays; the value itself is unused.
        let _ = state.tick
        let position = PlaybackDisplay.displayedPosition(progress: group.progress, state: group.playbackState, now: .now)
        let source = group.nowPlaying.flatMap(PlaybackDisplay.sourceLine(for:))
        VStack(spacing: 4) {
            if let position, let duration = group.progress.durationMillis {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary)
                        Capsule()
                            .fill(Color.primary.opacity(0.7))
                            .frame(width: geometry.size.width * CGFloat(position) / CGFloat(duration))
                    }
                }
                .frame(height: 3)
                .accessibilityElement()
                .accessibilityLabel("Progress")
                .accessibilityValue("\(PlaybackDisplay.timeString(millis: position)) of \(PlaybackDisplay.timeString(millis: duration))")
                HStack {
                    Text(PlaybackDisplay.timeString(millis: position)).accessibilityHidden(true)
                    Spacer()
                    if let source { Text(source).lineLimit(1) }
                    Spacer()
                    Text(PlaybackDisplay.remainingString(position: position, duration: duration)).accessibilityHidden(true)
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            } else if let source {
                Text(source)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }
}
