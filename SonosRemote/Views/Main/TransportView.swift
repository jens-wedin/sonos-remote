import SwiftUI
import SonosKit

/// Shuffle, previous, play/pause (56 pt), next, repeat. Disabled as a whole when there is no group.
struct TransportView: View {
    @Environment(AppState.self) private var state
    let group: SonosGroup?

    var body: some View {
        let progress = group?.progress
        let isPlaying = group?.playbackState == .playing
        HStack(spacing: 22) {
            ToggleGlyph(systemImage: "shuffle", label: "Shuffle", isOn: progress?.shuffle ?? false, enabled: progress?.canShuffle ?? false) { on in
                if let group { state.setShuffle(on, group: group.id) }
            }
            Button { if let group { state.previous(group: group.id) } } label: {
                Image(systemName: "backward.end.fill").font(.system(size: 18))
            }
            .accessibilityLabel("Previous track")

            Button { if let group { state.togglePlayPause(group: group.id) } } label: {
                // Explicit colours: a hierarchical `.primary` fill would resolve against the
                // glyph's foreground style and paint the circle the same colour as the glyph.
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .windowBackgroundColor))
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(Color(nsColor: .labelColor)))
            }
            .accessibilityLabel(isPlaying ? "Pause" : "Play")

            Button { if let group { state.next(group: group.id) } } label: {
                Image(systemName: "forward.end.fill").font(.system(size: 18))
            }
            .accessibilityLabel("Next track")
            ToggleGlyph(systemImage: "repeat", label: "Repeat", isOn: progress?.repeatEnabled ?? false, enabled: progress?.canRepeat ?? false) { on in
                if let group { state.setRepeat(on, group: group.id) }
            }
        }
        .buttonStyle(.borderless)
        .disabled(group == nil)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}

/// Shuffle / repeat: accent colour when on, disabled when the speaker cannot do it.
private struct ToggleGlyph: View {
    let systemImage: String
    let label: String
    let isOn: Bool
    let enabled: Bool
    let action: (Bool) -> Void

    var body: some View {
        Button { action(!isOn) } label: {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(!enabled ? Color.secondary.opacity(0.4) : isOn ? Color.accentColor : Color.secondary)
                .frame(width: 28, height: 28)
        }
        .disabled(!enabled)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "on" : "off")
    }
}
