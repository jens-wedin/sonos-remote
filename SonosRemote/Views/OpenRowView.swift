import SwiftUI
import SonosKit

struct OpenRowView: View {
    @Environment(AppState.self) private var state
    let group: SonosGroup

    var body: some View {
        @Bindable var state = state
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                Artwork(url: group.nowPlaying?.artworkURL, size: 64)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(group.name).font(.body.weight(.semibold)).lineLimit(1)
                        PlaybackBadge(state: group.playbackState)
                    }
                    if let now = group.nowPlaying {
                        Text(now.title).font(.callout.weight(.medium)).lineLimit(1)
                        Text([now.artist, now.album].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        Text([now.serviceName, now.containerName].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    } else {
                        Text("Not playing").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { state.toggleRow(group.id) }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Closes this room")
            }
            .padding(.top, 10)

            TransportView(group: group)

            VolumeSliderView(
                label: group.playerIDs.count > 1 ? "Group" : "Volume",
                volume: group.volume,
                accessibilityName: group.name,
                onChange: { state.setGroupVolume($0, group: group.id) },
                onMute: { state.setGroupMuted($0, group: group.id) }
            )

            if group.playerIDs.count > 1 {
                ForEach(group.playerIDs, id: \.self) { playerID in
                    if let player = state.snapshot.player(playerID) {
                        VolumeSliderView(
                            label: player.name,
                            volume: state.snapshot.playerVolumes[playerID] ?? .silent,
                            accessibilityName: player.name,
                            indent: true,
                            onChange: { state.setPlayerVolume($0, player: playerID) },
                            onMute: { state.setPlayerMuted($0, player: playerID) }
                        )
                    }
                }
            }

            Picker("Section", selection: $state.selectedTab) {
                ForEach(OpenRowTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.top, 4)
            .accessibilityLabel("Section")

            switch state.selectedTab {
            case .favorites: FavoritesTabView(group: group)
            case .eq: EQTabView(group: group)
            case .group: GroupTabView(group: group)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }
}
