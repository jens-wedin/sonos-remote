import SwiftUI

struct FooterView: View {
    var openSettings: () -> Void

    var body: some View {
        HStack {
            Button("Settings…", action: openSettings)
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .buttonStyle(.borderless)
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}
