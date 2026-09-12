import SwiftUI
import SonosKit

/// 96 pt artwork plus room, title, artist and album for the selected group.
struct HeroView: View {
    let group: SonosGroup?

    private var nowPlaying: NowPlaying? {
        guard let group, group.playbackState != .idle else { return nil }
        return group.nowPlaying
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Artwork(url: nowPlaying?.artworkURL, size: 96)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Image(systemName: "hifispeaker")
                    Text((group?.name ?? "No room selected").uppercased())
                }
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Color.supporting)
                .padding(.bottom, 2)
                if let now = nowPlaying {
                    Text(now.title).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                    if let artist = now.artist {
                        Text(artist).font(.callout).foregroundStyle(Color.supporting).lineLimit(1)
                    }
                    if let album = now.album ?? now.containerName {
                        Text(album).font(.caption).foregroundStyle(Color.faint).lineLimit(1)
                    }
                } else {
                    Text("Not playing").font(.system(size: 16, weight: .semibold)).foregroundStyle(Color.supporting)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 96)
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .accessibilityElement(children: .combine)
    }
}
