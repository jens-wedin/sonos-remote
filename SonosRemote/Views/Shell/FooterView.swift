import SwiftUI

struct FooterView: View {
    var body: some View {
        HStack {
            Text("Remote for Sonos \(AppVersion.short)").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.callout)
                .foregroundStyle(.secondary)
                .keyboardShortcut("q")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
