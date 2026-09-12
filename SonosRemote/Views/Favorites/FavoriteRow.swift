import SwiftUI
import SonosKit

/// One favorite: artwork or type glyph, name, second line, play. The whole row plays.
struct FavoriteRow: View {
    let favorite: Favorite
    let play: () -> Void

    var body: some View {
        Button(action: play) {
            HStack(spacing: 12) {
                Artwork(url: favorite.imageURL, size: 40, placeholder: favorite.kind.glyph)
                VStack(alignment: .leading, spacing: 2) {
                    Text(favorite.name).font(.callout.weight(.medium)).lineLimit(1)
                    if !favorite.secondLine.isEmpty {
                        Text(favorite.secondLine).font(.caption).foregroundStyle(Color.supporting).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "play.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .foregroundStyle(Color.supporting)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable()
        .accessibilityLabel("Play \(favorite.name)")
    }
}

extension Favorite.Kind {
    var glyph: String {
        switch self {
        case .station: "dot.radiowaves.left.and.right"
        case .playlist: "music.note.list"
        case .album: "opticaldisc"
        case .other: "music.note"
        }
    }

    var label: String? {
        switch self {
        case .station: "Station"
        case .playlist: "Playlist"
        case .album: "Album"
        case .other: nil
        }
    }
}

extension Favorite {
    /// "Sveriges Radio · Station": the subtitle (or the service when there is none) and the kind.
    var secondLine: String {
        [subtitle ?? serviceName, kind.label].compactMap { $0 }.joined(separator: " · ")
    }
}
