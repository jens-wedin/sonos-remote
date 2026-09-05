import SwiftUI
import SonosKit
import MenuBarExtraAccess
import KeyboardShortcuts

@main
struct SonosRemoteApp: App {
    @State private var appState = AppState.live()
    @State private var panel = PanelController()

    init() {
        let panel = PanelController()
        _panel = State(initialValue: panel)
        let appState = AppState.live()
        _appState = State(initialValue: appState)
        appState.start()
        KeyboardShortcuts.onKeyUp(for: .togglePanel) {
            Task { @MainActor in panel.toggle() }
        }
    }

    var body: some Scene {
        MenuBarExtra("Sonos", systemImage: "hifispeaker.2") {
            PanelView(closePanel: { panel.close() })
                .environment(appState)
                .environment(panel)
        }
        .menuBarExtraAccess(isPresented: $panel.isPresented)
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}
