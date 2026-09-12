import SwiftUI
import SonosKit
import MenuBarExtraAccess
import KeyboardShortcuts

@main
struct SonosRemoteApp: App {
    @State private var appState: AppState
    @State private var panel: PanelController
    @State private var updates: UpdateChecker

    init() {
        let panel = PanelController()
        _panel = State(initialValue: panel)
        let appState = AppState.live()
        _appState = State(initialValue: appState)
        appState.start()
        let updates = UpdateChecker.live()
        _updates = State(initialValue: updates)
        updates.start()
        KeyboardShortcuts.onKeyUp(for: .togglePanel) {
            Task { @MainActor in panel.toggle() }
        }
    }

    var body: some Scene {
        MenuBarExtra("Sonos", systemImage: "hifispeaker.2") {
            PanelShellView(closePanel: { panel.close() })
                .environment(appState)
                .environment(panel)
                .environment(updates)
        }
        .menuBarExtraAccess(isPresented: $panel.isPresented)
        .menuBarExtraStyle(.window)
    }
}
