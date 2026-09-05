import AppKit
import os

@MainActor
final class SettingsOpener {
    private var observer: (any NSObjectProtocol)?
    private let logger = Logger(subsystem: "com.jenswedin.SonosRemote", category: "settings")

    func open(closePanel: () -> Void) {
        closePanel()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if !NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
                _ = NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
            }
            self.watchForClose()
            self.verifySettingsWindowAppeared()
        }
    }

    /// Shared heuristic for recognizing the Settings window, used both while watching for
    /// its close and while confirming it actually appeared.
    private func isSettingsWindow(_ window: NSWindow) -> Bool {
        window.identifier?.rawValue.contains("Settings") == true || window.title == "Sonos Remote Settings"
    }

    private func watchForClose() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] notification in
            guard let window = notification.object as? NSWindow else { return }
            // queue: .main guarantees this runs on the main thread already; assumeIsolated
            // lets us read these MainActor-isolated AppKit properties without a Task hop.
            let isSettingsWindow = MainActor.assumeIsolated {
                self?.isSettingsWindow(window) ?? false
            }
            guard isSettingsWindow else { return }
            Task { @MainActor in
                NSApp.setActivationPolicy(.accessory)
                if let observer = self?.observer { NotificationCenter.default.removeObserver(observer) }
                self?.observer = nil
            }
        }
    }

    /// If neither `showSettingsWindow:` nor `showPreferencesWindow:` actually produced a
    /// visible Settings window, don't strand the app in `.regular` (Dock icon) with a dangling
    /// close observer — revert the activation policy and log the failure.
    private func verifySettingsWindowAppeared() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            let appeared = NSApp.windows.contains { $0.isVisible && self.isSettingsWindow($0) }
            guard !appeared else { return }
            NSApp.setActivationPolicy(.accessory)
            if let observer = self.observer {
                NotificationCenter.default.removeObserver(observer)
                self.observer = nil
            }
            self.logger.error("Settings window did not appear after showSettingsWindow:/showPreferencesWindow:")
        }
    }
}
