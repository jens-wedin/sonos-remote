import SwiftUI
import SonosKit

struct FavoritesTabView: View {
    @Environment(AppState.self) private var state
    let group: SonosGroup

    var body: some View {
        VStack(spacing: 0) {
            if state.snapshot.favorites.isEmpty {
                Text("No favorites in your Sonos system yet.")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
            ForEach(state.snapshot.favorites) { favorite in
                Button { state.playFavorite(favorite.id, group: group.id) } label: {
                    HStack(spacing: 10) {
                        Artwork(url: favorite.imageURL, size: 32)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(favorite.name).font(.callout).lineLimit(1)
                            if let subtitle = favorite.subtitle ?? favorite.serviceName {
                                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        Spacer()
                        Image(systemName: "play.fill").foregroundStyle(.tint).font(.caption)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 6)
                .accessibilityLabel("Play \(favorite.name) on \(group.name)")
                Divider()
            }
        }
    }
}
