import SwiftUI
import SonosKit

struct PanelView: View {
    @Environment(AppState.self) private var state
    let closePanel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sonos").font(.headline)
            Text(String(describing: state.snapshot.status)).foregroundStyle(.secondary)
            ForEach(state.snapshot.groups) { group in
                Text("\(group.name) · \(group.playbackState.rawValue)")
            }
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .padding(12)
        .frame(width: 340)
        .onExitCommand(perform: closePanel)
    }
}
