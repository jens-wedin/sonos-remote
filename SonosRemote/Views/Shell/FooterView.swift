import SwiftUI

struct FooterView: View {
    var body: some View {
        HStack {
            Text("Remote for Sonos \(AppVersion.short)").font(.caption).foregroundStyle(Color.supporting)
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .focusable()
                .font(.callout)
                .foregroundStyle(Color.supporting)
                .keyboardShortcut("q")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
