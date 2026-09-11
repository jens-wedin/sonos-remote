import SwiftUI
import SonosKit

struct FavoritesScreen: View {
    @Environment(AppState.self) private var state
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            StatusBannerView()
            Text("Favorites screen: replaced in Task 6").font(.caption).foregroundStyle(.secondary).padding(16)
        }
    }
}
