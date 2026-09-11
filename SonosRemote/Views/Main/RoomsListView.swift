import SwiftUI
import SonosKit

/// "ROOMS" with the Group link, then one row per group in AppState.orderedGroups. Up/Down move focus.
struct RoomsListView: View {
    @Environment(AppState.self) private var state
    @FocusState private var focusedGroupID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("ROOMS") {
                Button { state.show(.group) } label: {
                    Label("Group", systemImage: "link").font(.caption.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .disabled(state.selectedGroup == nil)
                .accessibilityLabel("Group rooms")
            }
            ForEach(state.orderedGroups) { group in
                RoomRowView(group: group, isSelected: group.id == state.selectedGroupID, focus: $focusedGroupID)
            }
        }
        .onMoveCommand { direction in
            let ids = state.orderedGroups.map(\.id)
            guard let current = focusedGroupID ?? state.selectedGroupID, let index = ids.firstIndex(of: current) else { return }
            switch direction {
            case .up where index > 0: focusedGroupID = ids[index - 1]
            case .down where index + 1 < ids.count: focusedGroupID = ids[index + 1]
            default: break
            }
        }
    }
}
