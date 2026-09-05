import SwiftUI
import SonosKit

struct GroupRowView: View {
    @Environment(AppState.self) private var state
    @Environment(\.isFocused) private var isFocused
    let group: SonosGroup

    var body: some View {
        VStack(spacing: 0) {
            if state.openGroupID == group.id {
                OpenRowView(group: group)
            } else {
                ClosedRowView(group: group)
            }
            if let error = state.rowErrors[group.id] {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
                    .accessibilityLabel("Error: \(error)")
            }
        }
        .background(state.openGroupID == group.id ? Color(nsColor: .controlBackgroundColor) : .clear)
        .focusable()
        .focusEffectDisabled()
        .overlay {
            if isFocused {
                RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor, lineWidth: 2).padding(2)
            }
        }
        .onKeyPress(.return) { state.toggleRow(group.id); return .handled }
        .onKeyPress(.space) { state.togglePlayPause(group: group.id); return .handled }
    }
}
