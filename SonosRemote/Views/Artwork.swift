import SwiftUI

struct Artwork: View {
    let url: URL?
    let size: CGFloat
    /// SF Symbol shown while there is no image: a note for tracks, a speaker for rooms, a radio for stations.
    var placeholder = "music.note"

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Rectangle().fill(.quaternary)
                    Image(systemName: placeholder).foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size > 48 ? 8 : 6, style: .continuous))
        .accessibilityHidden(true)
    }
}
