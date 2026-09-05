import Foundation
import Testing
@testable import SonosKit

@Suite struct ModelsTests {
    let decoder = JSONDecoder()

    @Test func decodesGroupsFixture() throws {
        let response = try decoder.decode(GroupsResponse.self, from: Fixtures.data("groups.json"))
        #expect(response.groups.count == 3)
        #expect(response.players.count == 4)
        let flyttbar = try #require(response.groups.first { $0.name == "Flyttbar + 1" })
        #expect(flyttbar.id == "RINCON_542A1B73A25001400:620674909")
        #expect(flyttbar.coordinatorId == "RINCON_542A1B73A25001400")
        #expect(flyttbar.playerIds == ["RINCON_347E5C04E98101400", "RINCON_542A1B73A25001400"])
        #expect(flyttbar.playbackState == "PLAYBACK_STATE_PLAYING")
        let stereo = try #require(response.players.first { $0.name == "Stereo" })
        #expect(stereo.websocketUrl == "wss://192.168.1.105:1443/websocket/api")
    }

    @Test func playerAddressComesFromWebsocketURL() {
        let wire = WirePlayer(id: "RINCON_1", name: "Stereo", websocketUrl: "wss://192.168.1.105:1443/websocket/api")
        let player = Player(wire: wire, hasSub: true)
        #expect(player.id == "RINCON_1")
        #expect(player.address == "192.168.1.105")
        #expect(player.hasSub)
        #expect(WirePlayer.host(fromWebsocketURL: "garbage") == nil)
    }

    @Test func decodesMetadataIntoNowPlaying() throws {
        let wire = try decoder.decode(WireMetadataStatus.self, from: Fixtures.data("playbackMetadata.json"))
        let nowPlaying = try #require(NowPlaying(wire: wire))
        #expect(nowPlaying.title == "Off the Wall")
        #expect(nowPlaying.artist == "Michael Jackson")
        #expect(nowPlaying.album == "Off the Wall")
        #expect(nowPlaying.artworkURL?.host == "i.scdn.co")
        #expect(nowPlaying.serviceName == "Spotify")
        #expect(nowPlaying.containerName == "R&B-mix")
    }

    @Test func metadataWithoutTrackOrContainerIsNil() {
        let wire = WireMetadataStatus(container: nil, currentItem: nil)
        #expect(NowPlaying(wire: wire) == nil)
    }

    @Test func radioMetadataFallsBackToContainerName() {
        let wire = WireMetadataStatus(
            container: WireContainer(name: "P3", service: WireService(name: "Sveriges Radio")),
            currentItem: WireQueueItem(track: WireTrack(name: nil, imageUrl: nil, album: nil, artist: nil, service: nil))
        )
        let nowPlaying = NowPlaying(wire: wire)
        #expect(nowPlaying?.title == "P3")
        #expect(nowPlaying?.serviceName == "Sveriges Radio")
    }

    @Test func decodesVolumeAndPlaybackStatus() throws {
        let volume = try decoder.decode(WireVolume.self, from: Fixtures.data("groupVolume.json"))
        #expect(Volume(wire: volume) == Volume(level: 5, muted: false, fixed: false))
        let status = try decoder.decode(WirePlaybackStatus.self, from: Fixtures.data("playback.json"))
        #expect(PlaybackState(wireValue: status.playbackState) == .playing)
        #expect(PlaybackState(wireValue: "PLAYBACK_STATE_SOMETHING_NEW") == .idle)
    }

    @Test func decodesFavorites() throws {
        let list = try decoder.decode(WireFavoritesList.self, from: Fixtures.data("favorites.json"))
        let favorites = list.items.map(Favorite.init(wire:))
        #expect(favorites.count == 1)
        #expect(favorites[0].id == "3")
        #expect(favorites[0].name == "P3")
        #expect(favorites[0].subtitle == "Sveriges Radio")
        #expect(favorites[0].serviceName == "Sveriges Radio")
        #expect(favorites[0].imageURL?.host == "static-cdn.sr.se")
    }

    @Test func decodesErrorBodies() throws {
        let type = try decoder.decode(WireObjectType.self, from: Fixtures.data("error_400_nokey.json"))
        #expect(type.objectType == "globalError")
        let global = try decoder.decode(WireGlobalError.self, from: Fixtures.data("error_400_nokey.json"))
        #expect(global.errorCode == "ERROR_API_KEY_VALIDATION_FAILED")
        let moved = try decoder.decode(WireCoordinatorChanged.self, from: Fixtures.data("error_404_coordinator_moved.json"))
        #expect(moved.groupStatus == "GROUP_STATUS_MOVED")
        #expect(moved.playerId == "RINCON_542A1B73A25001400")
        let gone = try decoder.decode(WireCoordinatorChanged.self, from: Fixtures.data("error_unknown_group.json"))
        #expect(gone.groupStatus == "GROUP_STATUS_GONE")
        #expect(gone.playerId == nil)
    }

    @Test func emptySnapshotDefaults() {
        let snapshot = HouseholdSnapshot()
        #expect(snapshot.status == .discovering)
        #expect(snapshot.groups.isEmpty)
        #expect(snapshot.playerVolumes.isEmpty)
    }
}
