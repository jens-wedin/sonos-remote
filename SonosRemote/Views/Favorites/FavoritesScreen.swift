import SwiftUI
import SonosKit

struct FavoritesScreen: View {
    @Environment(AppState.self) private var state

    private var filtered: [Favorite] { FavoritesFilter.apply(state.snapshot.favorites, query: state.favoritesSearch) }
    private var targetOptions: [(id: String, name: String)] { state.orderedGroups.map { ($0.id, $0.name) } }
    private var targetGroupID: String? { state.favoritesTargetGroupID ?? state.selectedGroupID }
    private var isSearching: Bool { !state.favoritesSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        @Bindable var state = state
        VStack(alignment: .leading, spacing: 0) {
            StatusBannerView()
            SectionLabel("PLAY TO") {
                RoomPicker(title: "Play to", selection: $state.favoritesTargetGroupID, options: targetOptions)
            }
            SearchField(text: $state.favoritesSearch, prompt: "Search favorites")
                .padding(.horizontal, 16)
            SectionLabel("ALL FAVORITES") {
                Text("\(filtered.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("\(filtered.count) favorites")
            }
            if filtered.isEmpty {
                Text(isSearching ? "No favorites match" : "No favorites in your Sonos system yet")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                Card {
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { index, favorite in
                        CardRow(isFirst: index == 0) {
                            FavoriteRow(favorite: favorite) { play(favorite) }
                        }
                    }
                }
            }
            if let targetGroupID, let error = state.rowErrors[targetGroupID] {
                ErrorLine(text: error)
            }
        }
        .padding(.bottom, 12)
    }

    private func play(_ favorite: Favorite) {
        guard let targetGroupID else { return }
        state.playFavorite(favorite.id, group: targetGroupID)
    }
}
