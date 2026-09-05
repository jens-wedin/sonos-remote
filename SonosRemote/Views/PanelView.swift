import SwiftUI
import SonosKit

struct PanelView: View {
    @Environment(AppState.self) private var state
    let closePanel: () -> Void
    var openSettings: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Sonos").font(.headline)
                Spacer()
                Text(roomCount).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .accessibilityAddTraits(.isHeader)

            StatusBannerView()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(state.snapshot.groups) { group in
                        Divider()
                        GroupRowView(group: group)
                    }
                }
            }
            .frame(maxHeight: 560)

            Divider()
            FooterView(openSettings: openSettings)
        }
        .frame(width: 340)
        .onExitCommand(perform: closePanel)
    }

    private var roomCount: String {
        let count = state.snapshot.players.count
        return count == 0 ? "" : "\(count) room\(count == 1 ? "" : "s")"
    }
}
