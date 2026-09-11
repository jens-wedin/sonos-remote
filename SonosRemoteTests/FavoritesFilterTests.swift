import Testing
import SonosKit
@testable import SonosRemote

@Suite struct FavoritesFilterTests {
    let favorites = [
        Favorite(id: "1", name: "P3", subtitle: "Sveriges Radio", serviceName: "Sveriges Radio", kind: .station),
        Favorite(id: "2", name: "Late Night Tapes", subtitle: "Playlist · 48 tracks", kind: .playlist),
        Favorite(id: "3", name: "Kitchen Jazz", subtitle: nil, serviceName: "Spotify", kind: .playlist),
    ]

    @Test func emptyQueryReturnsEverything() {
        #expect(FavoritesFilter.apply(favorites, query: "   ").map(\.id) == ["1", "2", "3"])
    }

    @Test func matchesNameSubtitleAndServiceCaseInsensitively() {
        #expect(FavoritesFilter.apply(favorites, query: "sveriges").map(\.id) == ["1"])
        #expect(FavoritesFilter.apply(favorites, query: "TAPES").map(\.id) == ["2"])
        #expect(FavoritesFilter.apply(favorites, query: "spotify").map(\.id) == ["3"])
        #expect(FavoritesFilter.apply(favorites, query: "zzz").isEmpty)
    }
}
