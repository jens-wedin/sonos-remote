import AppKit

@MainActor
final class SettingsOpener {
    private var observer: (any NSObjectProtocol)?

    func open(closePanel: () -> Void) {
        closePanel()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if !NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
                _ = NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
            }
            self.watchForClose()
        }
    }

    private func watchForClose() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] notification in
            guard let window = notification.object as? NSWindow else { return }
            // queue: .main guarantees this runs on the main thread already; assumeIsolated
            // lets us read these MainActor-isolated AppKit properties without a Task hop.
            let isSettingsWindow = MainActor.assumeIsolated {
                window.identifier?.rawValue.contains("Settings") == true || window.title == "Sonos Remote Settings"
            }
            guard isSettingsWindow else { return }
            Task { @MainActor in
                NSApp.setActivationPolicy(.accessory)
                if let observer = self?.observer { NotificationCenter.default.removeObserver(observer) }
                self?.observer = nil
            }
        }
    }
}
