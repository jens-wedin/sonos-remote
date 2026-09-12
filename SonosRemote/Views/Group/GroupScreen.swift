import SwiftUI
import SonosKit

struct GroupScreen: View {
    @Environment(AppState.self) private var state

    private var players: [Player] {
        state.players.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StatusBannerView()
            if let group = state.selectedGroup {
                HStack(spacing: 12) {
                    Artwork(url: group.nowPlaying?.artworkURL, size: 40, placeholder: "hifispeaker")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.name).font(.callout.weight(.semibold)).lineLimit(1)
                        Text(PlaybackDisplay.nowPlayingLine(for: group)).font(.caption).foregroundStyle(Color.supporting).lineLimit(1)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .accessibilityElement(children: .combine)

                SectionLabel("ROOMS PLAYING TOGETHER")
                Card {
                    ForEach(Array(players.enumerated()), id: \.element.id) { index, player in
                        CardRow(isFirst: index == 0) { MembershipRow(player: player, group: group) }
                    }
                }
                if let error = state.rowErrors[group.id] { ErrorLine(text: error) }
            } else {
                Text("No room selected")
                    .font(.callout)
                    .foregroundStyle(Color.supporting)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            }
        }
        .padding(.bottom, 12)
    }
}

/// Name, note, switch. The coordinator is on and disabled; a room playing elsewhere says so.
private struct MembershipRow: View {
    @Environment(AppState.self) private var state
    let player: Player
    let group: SonosGroup

    var body: some View {
        let isCoordinator = player.id == group.coordinatorID
        let isMember = group.playerIDs.contains(player.id)
        let elsewhere = state.group(containing: player.id)
        let playingElsewhere = !isMember && elsewhere?.playbackState == .playing
        VStack(alignment: .leading, spacing: 2) {
            Text(player.name).font(.callout)
            if isCoordinator {
                Text("Source of this group").font(.caption).foregroundStyle(Color.supporting)
            } else if playingElsewhere, let now = elsewhere?.nowPlaying {
                Text(verbatim: "Playing \(now.title), will switch to this group")
                    .font(.caption).foregroundStyle(Color.supporting).lineLimit(1)
            }
        }
        .accessibilityHidden(true)
        Spacer()
        Toggle(isOn: Binding(
            get: { isMember },
            set: { on in state.setMembership(of: player.id, inGroup: group.id, member: on) }
        )) { EmptyView() }
        .toggleStyle(.switch)
        .controlSize(.small)
        .labelsHidden()
        .disabled(isCoordinator)
        .accessibilityLabel(player.name)
        .accessibilityValue(isMember ? "in \(group.name)" : "not in \(group.name)")
        .accessibilityHint(isCoordinator ? "Source of this group" : (playingElsewhere ? "Playing elsewhere; switching it will move it to this group" : ""))
    }
}
