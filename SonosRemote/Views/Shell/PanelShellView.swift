import SwiftUI
import SonosKit

/// The whole panel: header, the current screen (sliding in and out), footer.
struct PanelShellView: View {
    @Environment(AppState.self) private var state
    @Environment(PanelController.self) private var panel
    @Environment(UpdateChecker.self) private var updates
    let closePanel: () -> Void

    @State private var bodyHeight: CGFloat = 0
    private static let maximumBodyHeight: CGFloat = 640
    @FocusState private var focus: PanelFocus?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(focus: $focus)
            Divider()
            ScrollView {
                screenView
                    .frame(width: 420)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bodyHeight = $0 }
            }
            .frame(height: min(bodyHeight, Self.maximumBodyHeight))
            .clipped()
            Divider()
            FooterView()
        }
        .frame(width: 420)
        .defaultFocus($focus, state.screen == .main ? .playPause : .back)
        .onExitCommand(perform: closePanel)
        .onChange(of: panel.isPresented, initial: true) { _, presented in
            state.setPanelPresented(presented)
            if presented { updates.checkIfDue() }
        }
        // Belt-and-braces: if the panel's window is torn down without `panel.isPresented`
        // flipping first, this still stops the once-a-second tick task. Idempotent with the
        // onChange above.
        .onDisappear { state.setPanelPresented(false) }
    }

    @ViewBuilder private var screenView: some View {
        ZStack(alignment: .top) {
            switch state.screen {
            case .main: MainScreen(focus: $focus).transition(transition(edge: .leading))
            case .favorites: FavoritesScreen().transition(transition(edge: .trailing))
            case .sound: SoundScreen().transition(transition(edge: .trailing))
            case .group: GroupScreen().transition(transition(edge: .trailing))
            case .settings: SettingsScreen().transition(transition(edge: .trailing))
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: state.screen)
    }

    private func transition(edge: Edge) -> AnyTransition {
        reduceMotion ? .opacity : .move(edge: edge)
    }
}
