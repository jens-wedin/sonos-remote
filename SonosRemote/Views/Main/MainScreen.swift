import SwiftUI
import SonosKit

struct MainScreen: View {
    @Environment(AppState.self) private var state
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            StatusBannerView()
            Text("Main screen: replaced in Task 5").font(.caption).foregroundStyle(.secondary).padding(16)
        }
    }
}
