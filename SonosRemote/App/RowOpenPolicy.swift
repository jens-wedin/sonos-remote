import SonosKit

enum RowOpenPolicy {
    static func resolve(remembered: String?, groups: [Group]) -> String? {
        if let remembered, groups.contains(where: { $0.id == remembered }) { return remembered }
        if let playing = groups.first(where: { $0.playbackState == .playing }) { return playing.id }
        return groups.first?.id
    }
}
