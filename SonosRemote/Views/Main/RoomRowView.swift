import SwiftUI
import SonosKit

/// One group: art, name, now-playing line, compact slider. Art and text select; the slider does not.
struct RoomRowView: View {
    @Environment(AppState.self) private var state
    let group: SonosGroup
    let isSelected: Bool
    let focus: FocusState<String?>.Binding

    private var line: String { PlaybackDisplay.nowPlayingLine(for: group) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { state.select(group.id) } label: {
                    HStack(spacing: 12) {
                        Artwork(url: group.nowPlaying?.artworkURL, size: 40, placeholder: "hifispeaker")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.name).font(.callout.weight(.semibold)).lineLimit(1)
                            Text(line).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 8)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // Full Keyboard Access is off by default, which leaves a plain macOS button
                // untabbable; .focusable() makes it reachable regardless, so Up/Down (via
                // RoomsListView's onMoveCommand) and this row's own onKeyPress handlers work.
                .focusable()
                .focused(focus, equals: group.id)
                .onKeyPress(.space) { state.togglePlayPause(group: group.id); return .handled }
                .onKeyPress(.return) { state.select(group.id); return .handled }
                .accessibilityLabel("\(group.name), \(line)")
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])

                VolumeSliderView(
                    label: group.name,
                    volume: group.volume,
                    accessibilityName: group.name,
                    style: .compact,
                    onChange: { state.setGroupVolume($0, group: group.id) },
                    onMute: { state.setGroupMuted($0, group: group.id) }
                )
                .frame(width: 130)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isSelected ? AnyShapeStyle(.quaternary.opacity(0.6)) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.horizontal, 8)
            if let error = state.rowErrors[group.id] { ErrorLine(text: error) }
        }
    }
}
