import SwiftUI
import SonosKit

struct SoundScreen: View {
    @Environment(AppState.self) private var state
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            StatusBannerView()
            Text("Sound screen: replaced in Task 7").font(.caption).foregroundStyle(.secondary).padding(16)
        }
    }
}
