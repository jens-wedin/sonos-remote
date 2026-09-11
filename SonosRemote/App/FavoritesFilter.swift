import Foundation
import SonosKit

enum FavoritesFilter {
    static func apply(_ favorites: [Favorite], query: String) -> [Favorite] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return favorites }
        return favorites.filter { favorite in
            [favorite.name, favorite.subtitle ?? "", favorite.serviceName ?? ""]
                .contains { $0.lowercased().contains(needle) }
        }
    }
}
