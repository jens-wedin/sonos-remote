import SwiftUI
import SonosKit

struct MainScreen: View {
    @Environment(AppState.self) private var state
    @Environment(UpdateChecker.self) private var updates
    let focus: FocusState<PanelFocus?>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StatusBannerView()
            if let release = updates.available {
                UpdateCard(release: release, onCopy: { updates.copyCommand() }, onDismiss: { updates.dismiss() })
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
    }
}
