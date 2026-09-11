import Foundation

extension Volume {
    init(wire: WireVolume) {
        self.init(level: wire.volume, muted: wire.muted, fixed: wire.fixed)
    }
}

extension Player {
    init(wire: WirePlayer, hasSub: Bool) {
        self.init(id: wire.id, name: wire.name, address: WirePlayer.host(fromWebsocketURL: wire.websocketUrl) ?? "", hasSub: hasSub)
    }
}

extension NowPlaying {
    /// nil when there is neither a track name nor a container name (nothing loaded).
    init?(wire: WireMetadataStatus) {
        let track = wire.currentItem?.track
        guard let title = track?.name ?? wire.container?.name, !title.isEmpty else { return nil }
        self.init(
            title: title,
            artist: track?.artist?.name,
            album: track?.album?.name,
            artworkURL: track?.imageUrl.flatMap(URL.init(string:)),
            serviceName: track?.service?.name ?? wire.container?.service?.name,
            containerName: wire.container?.name
        )
    }
}

extension Favorite {
    init(wire: WireFavorite) {
        self.init(
            id: wire.id,
            name: wire.name,
            subtitle: wire.description,
            imageURL: wire.imageUrl.flatMap(URL.init(string:)),
            serviceName: wire.service?.name,
            kind: Kind(resourceType: wire.resource?.type)
        )
    }
}

extension PlaybackProgress {
    /// Builds a report from a playbackStatus body; duration is unknown here (it comes from metadata).
    init(wire: WirePlaybackStatus, reportedAt: Date) {
        self.init(
            positionMillis: PlaybackProgress.clamped(wire.positionMillis ?? 0),
            durationMillis: nil,
            reportedAt: reportedAt,
            shuffle: wire.playModes?.shuffle ?? false,
            repeatEnabled: wire.playModes?.repeat ?? false,
            canShuffle: wire.availablePlaybackActions?.canShuffle ?? false,
            canRepeat: wire.availablePlaybackActions?.canRepeat ?? false
        )
    }
}
