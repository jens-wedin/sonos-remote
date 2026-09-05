import AppKit
import SwiftUI
import os

/// Shows the Settings window from a Dock-less (accessory) app.
///
/// The app opens a regular SwiftUI `Window` scene (id `settings`) rather than the `Settings`
/// scene: the private `showSettingsWindow:` action is unreliable from a `MenuBarExtra` on
/// macOS 26 and, even when it works, the window can open behind everything else. Here the
/// app becomes a regular app while the window is open, brings the window to the front
/// explicitly, and returns to accessory mode when it closes.
@MainActor
final class SettingsOpener {
    static let windowID = "settings"
    static let windowTitle = "Sonos Remote Settings"

    private var observer: (any NSObjectProtocol)?
    private let logger = Logger(subsystem: "com.jenswedin.SonosRemote", category: "settings")

    func open(closePanel: () -> Void, openWindow: OpenWindowAction) {
        closePanel()
        NSApp.setActivationPolicy(.regular)
        openWindow(id: Self.windowID)
        NSApp.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if let window = NSApp.windows.first(where: { self.isSettingsWindow($0) }) {
                window.center()
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
                NSApp.activate()
            }
            self.watchForClose()
            self.verifySettingsWindowAppeared()
        }
    }

    /// Shared heuristic for recognizing the Settings window, used both while watching for
    /// its close and while confirming it actually appeared.
    private func isSettingsWindow(_ window: NSWindow) -> Bool {
        window.identifier?.rawValue.lowercased().contains(Self.windowID) == true || window.title == Self.windowTitle
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

    /// If no visible Settings window exists two seconds later, don't strand the app in
    /// `.regular` (Dock icon) with a dangling close observer — revert and log the failure.
    private func verifySettingsWindowAppeared() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            let appeared = NSApp.windows.contains { $0.isVisible && self.isSettingsWindow($0) }
            guard !appeared else { return }
            NSApp.setActivationPolicy(.accessory)
            if let observer = self.observer {
                NotificationCenter.default.removeObserver(observer)
                self.observer = nil
            }
            self.logger.error("Settings window did not appear after openWindow(id: \"settings\")")
        }
    }
}
