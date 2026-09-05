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

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(state.snapshot.groups) { group in
                            Divider()
                            GroupRowView(group: group)
                                .focused($focusedGroupID, equals: group.id)
                                .id(group.id)
                        }
                    }
                }
                .frame(maxHeight: 560)
                .onKeyPress(.downArrow) { move(by: 1); proxy.scrollTo(focusedGroupID); return .handled }
                .onKeyPress(.upArrow) { move(by: -1); proxy.scrollTo(focusedGroupID); return .handled }
            }

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

    @FocusState private var focusedGroupID: String?

    private func move(by offset: Int) {
        let ids = state.snapshot.groups.map(\.id)
        guard !ids.isEmpty else { return }
        guard let current = focusedGroupID, let index = ids.firstIndex(of: current) else {
            focusedGroupID = ids.first
            return
        }
        focusedGroupID = ids[max(0, min(ids.count - 1, index + offset))]
    }
}
