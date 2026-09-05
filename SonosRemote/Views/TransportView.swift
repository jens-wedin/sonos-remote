import SwiftUI
import SonosKit

struct TransportView: View {
    @Environment(AppState.self) private var state
    let group: SonosGroup

    var body: some View {
        HStack(spacing: 26) {
            Button { state.previous(group: group.id) } label: {
                Image(systemName: "backward.fill").font(.title3)
            }
            .accessibilityLabel("Previous track")

            Button { state.togglePlayPause(group: group.id) } label: {
                Image(systemName: group.playbackState == .playing ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(.primary))
                    .foregroundStyle(Color(nsColor: .windowBackgroundColor))
            }
            .accessibilityLabel(group.playbackState == .playing ? "Pause" : "Play")

            Button { state.next(group: group.id) } label: {
                Image(systemName: "forward.fill").font(.title3)
            }
            .accessibilityLabel("Next track")
        }
        .buttonStyle(.borderless)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }
}
