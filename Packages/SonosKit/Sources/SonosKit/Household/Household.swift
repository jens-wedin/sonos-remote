import Foundation

public enum HouseholdError: Error, Hashable, Sendable {
    case unknownGroup
    case unknownPlayer
    case notReady
}

/// Owns discovery, one socket per player, the REST and UPnP clients, and the snapshot.
/// Everything the app needs goes through here.
public actor Household {
    public struct Configuration: Sendable {
        public var discoveryTimeout: Duration = .seconds(10)
        public var backoff = Backoff()
        public init() {}
    }

    private let discovery: any Discovering
    private let transport: any Transport
    private let trustStore: TrustStore?
    private let configuration: Configuration
    private let api: LocalAPIClient
    private let upnp: UPnPClient

    private var snapshot = HouseholdSnapshot()
    private var observers: [UUID: AsyncStream<HouseholdSnapshot>.Continuation] = [:]
    private var sockets: [String: PlayerSocket] = [:]
    private var socketTasks: [String: Task<Void, Never>] = [:]
    private var gatewayID: String?
    private var addresses: [String: String] = [:]
    private var subProbed: Set<String> = []
    /// Players discovery has told us are gone. Discovery is authoritative for physical
    /// presence, so a topology fetch or `.groups` socket push that still lists one of these
    /// (because it raced ahead of, or was queued before, the `.lost` event) has it filtered
    /// out rather than resurrecting a player we already know left. Cleared when discovery
    /// reports the player `.found` again.
    private var removedPlayers: Set<String> = []
    private var discoveryTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var started = false

    public init(discovery: any Discovering, transport: any Transport, trustStore: TrustStore? = nil, configuration: Configuration = .init()) {
        self.discovery = discovery
        self.transport = transport
        self.trustStore = trustStore
        self.configuration = configuration
        self.api = LocalAPIClient(transport: transport)
        self.upnp = UPnPClient(transport: transport)
    }

    // MARK: Lifecycle

    public var current: HouseholdSnapshot { snapshot }

    public func snapshots() -> AsyncStream<HouseholdSnapshot> {
        let (stream, continuation) = AsyncStream<HouseholdSnapshot>.makeStream()
        let id = UUID()
        observers[id] = continuation
        continuation.yield(snapshot)
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeObserver(id) }
        }
        return stream
    }

    public func start() {
        guard !started else { return }
        started = true
        apply(.status(.discovering))
        discoveryTask = Task { [weak self] in
            guard let self else { return }
            for await event in discovery.events() {
                await self.handle(discovery: event)
            }
        }
        timeoutTask = Task { [weak self, configuration] in
            do {
                try await Task.sleep(for: configuration.discoveryTimeout)
            } catch {
                return
            }
            await self?.discoveryTimedOut()
        }
    }

    public func stop() {
        discoveryTask?.cancel()
        timeoutTask?.cancel()
        discovery.stop()
        for (id, socket) in sockets {
            socketTasks[id]?.cancel()
            Task { await socket.stop() }
        }
        sockets = [:]
        socketTasks = [:]
        for continuation in observers.values { continuation.finish() }
        observers = [:]
        started = false
        gatewayID = nil
        removedPlayers = []
        subProbed = []
    }

    // MARK: Commands

    public func play(group id: String) async throws { try await groupCommand(id) { try await api.play(groupID: id, at: $0) } }
    public func pause(group id: String) async throws { try await groupCommand(id) { try await api.pause(groupID: id, at: $0) } }
    public func next(group id: String) async throws { try await groupCommand(id) { try await api.next(groupID: id, at: $0) } }
    public func previous(group id: String) async throws { try await groupCommand(id) { try await api.previous(groupID: id, at: $0) } }

    public func setGroupVolume(_ level: Int, group id: String) async throws {
        try await groupCommand(id) { try await api.setGroupVolume(level, groupID: id, at: $0) }
    }

    public func setGroupMuted(_ muted: Bool, group id: String) async throws {
        try await groupCommand(id) { try await api.setGroupMuted(muted, groupID: id, at: $0) }
    }

    public func playFavorite(_ favoriteID: String, group id: String) async throws {
        try await groupCommand(id) { try await api.loadFavorite(favoriteID, groupID: id, at: $0) }
    }

    public func setGroupMembers(_ playerIDs: [String], group id: String) async throws {
        try await groupCommand(id) { try await api.setGroupMembers(playerIDs, groupID: id, at: $0) }
    }

    public func setPlayerVolume(_ level: Int, player id: String) async throws {
        try await api.setPlayerVolume(level, playerID: id, at: playerAddress(id))
    }

    public func setPlayerMuted(_ muted: Bool, player id: String) async throws {
        try await api.setPlayerMuted(muted, playerID: id, at: playerAddress(id))
    }

    public func eq(player id: String) async throws -> EQSettings {
        let player = try requirePlayer(id)
        return try await upnp.eqSettings(address: player.address, hasSub: player.hasSub)
    }

    public func setEQ(_ eq: EQSettings, player id: String) async throws {
        try await upnp.apply(eq, address: playerAddress(id))
    }

    // MARK: Discovery handling

    private func handle(discovery event: DiscoveryEvent) async {
        switch event {
        case .found(let player):
            removedPlayers.remove(player.id)
            addresses[player.id] = player.address
            trustStore?.allow(host: player.address)
            if gatewayID == nil {
                gatewayID = player.id
                timeoutTask?.cancel()
                await refreshTopology()
                await refreshFavorites()
            }
        case .lost(let playerID):
            removedPlayers.insert(playerID)
            subProbed.remove(playerID)
            apply(.playerRemoved(playerID: playerID))
            await stopSocket(playerID)
            if gatewayID == playerID { gatewayID = snapshot.players.first?.id }
            await reconcileSubscriptions()
        case .permissionDenied:
            apply(.status(.localNetworkDenied))
        }
    }

    private func discoveryTimedOut() {
        if snapshot.players.isEmpty, snapshot.status == .discovering {
            apply(.status(.noPlayersFound))
        }
    }

    // MARK: REST refreshes

    private func refreshTopology() async {
        guard let gateway = gatewayAddress() else { return }
        do {
            let response = try await api.groups(from: gateway)
            allowTrust(forWirePlayers: response.players)
            let filtered = excludingRemovedPlayers(groups: response.groups, players: response.players)
            apply(.topology(groups: filtered.groups, players: filtered.players))
            for player in snapshot.players {
                addresses[player.id] = player.address
                trustStore?.allow(host: player.address)
            }
            if snapshot.status != .ready { apply(.status(.ready)) }
            await ensureSockets()
            await reconcileSubscriptions()
            await probeSubs()
        } catch LocalAPIError.invalidAPIKey, LocalAPIError.unauthorized {
            apply(.status(.unauthorized))
        } catch {
            // Keep the previous snapshot; the next socket event or command will retry.
        }
    }

    private func refreshFavorites() async {
        guard let gateway = gatewayAddress() else { return }
        if let favorites = try? await api.favorites(from: gateway) {
            apply(.favorites(favorites))
        }
    }

    private func probeSubs() async {
        for player in snapshot.players where !subProbed.contains(player.id) {
            subProbed.insert(player.id)
            let hasSub = (try? await upnp.hasSub(address: player.address)) ?? false
            apply(.playerHasSub(playerID: player.id, hasSub: hasSub))
        }
    }

    // MARK: Sockets

    private func ensureSockets() async {
        let wanted = Set(snapshot.players.map(\.id))
        for id in Set(sockets.keys).subtracting(wanted) {
            await stopSocket(id)
        }
        for player in snapshot.players where sockets[player.id] == nil {
            let socket = PlayerSocket(playerID: player.id, address: player.address, transport: transport, backoff: configuration.backoff)
            sockets[player.id] = socket
            socketTasks[player.id] = Task { [weak self] in
                for await output in socket.outputs {
                    guard let self else { return }
                    await self.handle(socketOutput: output, from: player.id)
                }
            }
            await socket.start()
        }
    }

    private func stopSocket(_ playerID: String) async {
        socketTasks[playerID]?.cancel()
        socketTasks[playerID] = nil
        if let socket = sockets.removeValue(forKey: playerID) {
            await socket.stop()
        }
    }

    private func reconcileSubscriptions() async {
        let plan = SubscriptionPlan.make(groups: snapshot.groups, players: snapshot.players, gatewayID: gatewayID)
        for (id, socket) in sockets {
            await socket.setSubscriptions(plan[id] ?? [])
        }
    }

    private func handle(socketOutput output: PlayerSocket.Output, from playerID: String) async {
        guard case .event(let event) = output else { return }
        switch event {
        case .playbackStatus(let groupID, let state):
            apply(.playbackStatus(groupID: groupID, state: state))
        case .metadata(let groupID, let nowPlaying):
            apply(.metadata(groupID: groupID, nowPlaying: nowPlaying))
        case .groupVolume(let groupID, let volume):
            apply(.groupVolume(groupID: groupID, volume: volume))
        case .playerVolume(let id, let volume):
            apply(.playerVolume(playerID: id, volume: volume))
        case .groups(let groups, let players):
            allowTrust(forWirePlayers: players)
            let filtered = excludingRemovedPlayers(groups: groups, players: players)
            apply(.topology(groups: filtered.groups, players: filtered.players))
            for player in snapshot.players {
                addresses[player.id] = player.address
                trustStore?.allow(host: player.address)
            }
            await ensureSockets()
            await reconcileSubscriptions()
            await probeSubs()
        case .favoritesChanged:
            await refreshFavorites()
        case .subscribed, .globalError, .unknown:
            break
        }
    }

    // MARK: Helpers

    private func apply(_ event: HouseholdEvent) {
        snapshot = SnapshotReducer.reduce(snapshot, event)
        for continuation in observers.values {
            continuation.yield(snapshot)
        }
    }

    /// Allows every address in a raw topology payload, before `removedPlayers` filtering, so a
    /// topology-listed player address is always trusted even if it's currently filtered out of
    /// the snapshot.
    private func allowTrust(forWirePlayers players: [WirePlayer]) {
        for player in players {
            if let address = WirePlayer.host(fromWebsocketURL: player.websocketUrl) {
                trustStore?.allow(host: address)
            }
        }
    }

    /// Drops any player discovery has told us is gone from a topology payload (and prunes
    /// groups left with no players), so a REST fetch or `.groups` socket push that raced
    /// ahead of (or was queued before) the matching `.lost` event can't resurrect it.
    private func excludingRemovedPlayers(groups: [WireGroup], players: [WirePlayer]) -> (groups: [WireGroup], players: [WirePlayer]) {
        guard !removedPlayers.isEmpty else { return (groups, players) }
        let filteredPlayers = players.filter { !removedPlayers.contains($0.id) }
        let filteredGroups = groups.compactMap { group -> WireGroup? in
            var group = group
            group.playerIds.removeAll { removedPlayers.contains($0) }
            return group.playerIds.isEmpty ? nil : group
        }
        return (filteredGroups, filteredPlayers)
    }

    private func removeObserver(_ id: UUID) {
        observers[id] = nil
    }

    private func gatewayAddress() -> String? {
        guard let gatewayID else { return nil }
        return addresses[gatewayID]
    }

    private func requirePlayer(_ id: String) throws -> Player {
        guard let player = snapshot.player(id) else { throw HouseholdError.unknownPlayer }
        return player
    }

    private func playerAddress(_ id: String) throws -> String {
        try requirePlayer(id).address
    }

    private func coordinatorAddress(for groupID: String) -> String? {
        guard let group = snapshot.group(groupID) else { return nil }
        return snapshot.player(group.coordinatorID)?.address ?? addresses[group.coordinatorID]
    }

    /// Runs `operation` against the coordinator; on a coordinator change, refreshes topology and retries once.
    private func groupCommand(_ groupID: String, _ operation: @Sendable (String) async throws -> Void) async throws {
        guard let address = coordinatorAddress(for: groupID) else { throw HouseholdError.unknownGroup }
        do {
            try await operation(address)
        } catch LocalAPIError.coordinatorMoved, LocalAPIError.groupGone {
            await refreshTopology()
            guard let retryAddress = coordinatorAddress(for: groupID) else { throw HouseholdError.unknownGroup }
            try await operation(retryAddress)
        }
    }
}
