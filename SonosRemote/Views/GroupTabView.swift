import SwiftUI
import SonosKit

struct GroupTabView: View {
    @Environment(AppState.self) private var state
    let group: SonosGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("ROOMS PLAYING TOGETHER")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.vertical, 6)
                .accessibilityAddTraits(.isHeader)
            ForEach(state.snapshot.players) { player in
                let isCoordinator = player.id == group.coordinatorID
                let isMember = group.playerIDs.contains(player.id)
                let elsewhere = state.snapshot.group(containing: player.id)
                let playingElsewhere = !isMember && elsewhere?.playbackState == .playing
                HStack(alignment: .top, spacing: 10) {
                    Toggle(isOn: Binding(
                        get: { isMember },
                        set: { on in state.setMembership(of: player.id, inGroup: group.id, member: on) }
                    )) { EmptyView() }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .disabled(isCoordinator)
                    .accessibilityLabel(membershipLabel(player, isCoordinator: isCoordinator))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(player.name).font(.callout)
                        if isCoordinator {
                            Text("Source of this group").font(.caption).foregroundStyle(.secondary)
                        } else if playingElsewhere, let now = elsewhere?.nowPlaying {
                            Text("Playing \(now.title), will switch to this group").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 6)
                Divider()
            }
        }
    }

    private func membershipLabel(_ player: Player, isCoordinator: Bool) -> String {
        isCoordinator ? "\(player.name), source of this group" : "\(player.name) in \(group.name)"
    }
}
