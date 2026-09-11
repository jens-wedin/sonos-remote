import SwiftUI
import SonosKit

/// Temporary stub while the new shell is built (Task 4 replaces this file).
struct PanelView: View {
    @Environment(AppState.self) private var state
    let closePanel: () -> Void
    var openSettings: (OpenWindowAction) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Redesign in progress").font(.headline)
            Text(state.selectedGroup?.name ?? "No room").foregroundStyle(.secondary)
            StatusBannerView()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .padding(12)
        .frame(width: 420)
        .onExitCommand(perform: closePanel)
    }
}
