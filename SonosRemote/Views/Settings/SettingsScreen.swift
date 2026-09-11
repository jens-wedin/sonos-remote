import SwiftUI
import SonosKit

struct SettingsScreen: View {
    @Environment(AppState.self) private var state
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            StatusBannerView()
            Text("Settings screen: replaced in Task 9").font(.caption).foregroundStyle(.secondary).padding(16)
        }
    }
}
