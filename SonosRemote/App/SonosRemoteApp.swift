import SwiftUI
import SonosKit
import MenuBarExtraAccess
import KeyboardShortcuts

@main
struct SonosRemoteApp: App {
    @State private var appState: AppState
    @State private var panel: PanelController
    @State private var settingsOpener: SettingsOpener

    init() {
        let panel = PanelController()
        _panel = State(initialValue: panel)
        let appState = AppState.live()
        _appState = State(initialValue: appState)
        appState.start()
        _settingsOpener = State(initialValue: SettingsOpener())
        KeyboardShortcuts.onKeyUp(for: .togglePanel) {
            Task { @MainActor in panel.toggle() }
        }
    }

    var body: some Scene {
        MenuBarExtra("Sonos", systemImage: "hifispeaker.2") {
            PanelView(closePanel: { panel.close() }, openSettings: { settingsOpener.open(closePanel: { panel.close() }) })
                .environment(appState)
                .environment(panel)
        }
        .menuBarExtraAccess(isPresented: $panel.isPresented)
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView().navigationTitle("Sonos Remote Settings")
        }
    }
}
