import Observation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let togglePanel = Self("togglePanel")
}

/// Bridges MenuBarExtraAccess's isPresented binding with the global shortcut and Escape.
@MainActor @Observable
final class PanelController {
    var isPresented = false

    func toggle() { isPresented.toggle() }
    func close() { isPresented = false }
}
