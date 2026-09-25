import SwiftUI
import SonosKit

struct MainScreen: View {
    @Environment(AppState.self) private var state
    @Environment(UpdateController.self) private var updates
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let focus: FocusState<PanelFocus?>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StatusBannerView()
            if updates.state != .idle {
                UpdateCard()
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
            HeroView(group: state.selectedGroup)
            if let group = state.selectedGroup {
                ProgressBarView(group: group)
            }
            TransportView(group: state.selectedGroup, focus: focus)
            if let group = state.selectedGroup {
                VolumeRowView(group: group)
            }
            if !state.groups.isEmpty {
                RoomsListView()
            }
        }
        .padding(.bottom, 12)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: updates.state == .idle)
    }
}
