import SwiftUI
import SonosKit

struct GroupScreen: View {
    @Environment(AppState.self) private var state
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            StatusBannerView()
            Text("Group screen: replaced in Task 8").font(.caption).foregroundStyle(.secondary).padding(16)
        }
    }
}
