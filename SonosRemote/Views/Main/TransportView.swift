import SwiftUI
import SonosKit

/// Shuffle, previous, play/pause (56 pt), next, repeat. Disabled as a whole when there is no group.
struct TransportView: View {
    @Environment(AppState.self) private var state
    let group: SonosGroup?
    let focus: FocusState<PanelFocus?>.Binding

    var body: some View {
        let progress = group?.progress
        let isPlaying = group?.playbackState == .playing
        HStack(spacing: 22) {
            ToggleGlyph(systemImage: "shuffle", label: "Shuffle", isOn: progress?.shuffle ?? false, enabled: progress?.canShuffle ?? false) { on in
                if let group { state.setShuffle(on, group: group.id) }
            }
            Button { if let group { state.previous(group: group.id) } } label: {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 18))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .focusable()
            .keyboardShortcut(.leftArrow, modifiers: .command)
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
            .buttonStyle(.borderless)
            .focusable()
            .focused(focus, equals: .playPause)
            .keyboardShortcut(.space, modifiers: [])
            .accessibilityLabel(isPlaying ? "Pause" : "Play")

            Button { if let group { state.next(group: group.id) } } label: {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 18))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .focusable()
            .keyboardShortcut(.rightArrow, modifiers: .command)
            .accessibilityLabel("Next track")
            ToggleGlyph(systemImage: "repeat", label: "Repeat", isOn: progress?.repeatEnabled ?? false, enabled: progress?.canRepeat ?? false) { on in
                if let group { state.setRepeat(on, group: group.id) }
            }
        }
        .disabled(group == nil)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}

/// Shuffle / repeat: accent colour plus a background fill when on (not colour alone), disabled
/// when the speaker cannot do it.
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
                .foregroundStyle(isOn ? Color.accentColor : Color.supporting)
                .opacity(enabled ? 1 : Palette.disabledOpacity)
                .frame(width: 28, height: 28)
                .background(isOn ? AnyShapeStyle(Color.accentColor.opacity(0.18)) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .focusable()
        .disabled(!enabled)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "on" : "off")
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}
