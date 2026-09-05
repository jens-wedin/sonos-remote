import SwiftUI
import SonosKit

struct ClosedRowView: View {
    @Environment(AppState.self) private var state
    let group: SonosGroup

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                Artwork(url: group.nowPlaying?.artworkURL, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(group.name).font(.body.weight(.semibold)).lineLimit(1)
                        PlaybackBadge(state: group.playbackState)
                    }
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { state.toggleRow(group.id) }
            VolumeSliderView(
                label: "",
                volume: group.volume,
                accessibilityName: group.name,
                compact: true,
                onChange: { state.setGroupVolume($0, group: group.id) },
                onMute: { state.setGroupMuted($0, group: group.id) }
            )
            .frame(width: 130)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(group.name), \(stateDescription), \(subtitle)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Open") { state.toggleRow(group.id) }
    }

    private var subtitle: String {
        guard let now = group.nowPlaying else { return "Not playing" }
        let parts = [now.title, now.artist ?? ""].filter { !$0.isEmpty }
        if !parts.isEmpty { return parts.joined(separator: " · ") }
        return now.containerName ?? "Now playing"
    }

    private var stateDescription: String {
        switch group.playbackState {
        case .playing: "playing"
        case .paused: "paused"
        case .buffering: "buffering"
        case .idle: "not playing"
        }
    }
}

struct PlaybackBadge: View {
    let state: PlaybackState

    var body: some View {
        switch state {
        case .playing:
            Text("PLAYING").badgeStyle(.green)
        case .paused:
            Text("PAUSED").badgeStyle(.gray)
        case .buffering:
            Text("LOADING").badgeStyle(.gray)
        case .idle:
            EmptyView()
        }
    }
}

private extension Text {
    func badgeStyle(_ color: Color) -> some View {
        self.font(.system(size: 9, weight: .bold))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color, in: RoundedRectangle(cornerRadius: 3))
            .accessibilityHidden(true)
    }
}
