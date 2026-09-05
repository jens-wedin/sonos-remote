import Foundation
import os

public enum HouseholdError: Error, Hashable, Sendable {
    case unknownGroup
    case unknownPlayer
    case notReady
}

/// Owns discovery, one socket per player, the REST and UPnP clients, and the snapshot.
/// Everything the app needs goes through here.
public actor Household {
    private let logger = Logger(subsystem: "com.jenswedin.SonosRemote", category: "household")

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
    /// Ids currently awaiting a sub probe response, so a `probeSubs()` call that starts while
    /// an earlier one is still awaiting the same player's probe doesn't fire a duplicate request.
    private var subProbeInFlight: Set<String> = []
    /// Players discovery has told us are gone. Discovery is authoritative for physical
    /// presence, so a topology fetch or `.groups` socket push that still lists one of these
    /// (because it raced ahead of, or was queued before, the `.lost` event) has it filtered
    /// out rather than resurrecting a player we already know left. Cleared when discovery
    /// reports the player `.found` again.
    private var removedPlayers: Set<String> = []
    private var discoveryTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    /// Retries the initial (and any post-`.noPlayersFound`) topology fetch until it succeeds,
    /// is unauthorized, or is cancelled. Once `.ready`, later failures are covered by the
    /// per-player socket reconnect logic instead.
    private var bootstrapTask: Task<Void, Never>?
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
        armDiscoveryTimeout()
    }

    public func stop() {
        discoveryTask?.cancel()
        timeoutTask?.cancel()
        bootstrapTask?.cancel()
        bootstrapTask = nil
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
        subProbeInFlight = []
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
            logger.info("discovery found player \(player.id, privacy: .public) at \(player.address, privacy: .public)")
            removedPlayers.remove(player.id)
            addresses[player.id] = player.address
            trustStore?.allow(host: player.address)
            if snapshot.status == .noPlayersFound {
                // A player (re)announced after every fetch had failed and the timeout gave up;
                // give bootstrapping another chance. Covers both the common case (some other
                // player is still the gateway) and the case where every previously-known player
                // was lost in the meantime (gatewayID is nil here too).
                if gatewayID == nil { gatewayID = player.id }
                apply(.status(.discovering))
                armDiscoveryTimeout()
                startBootstrap()
            } else if gatewayID == nil {
                gatewayID = player.id
                startBootstrap()
            }
        case .lost(let playerID):
            logger.info("discovery lost player \(playerID, privacy: .public)")
            removedPlayers.insert(playerID)
            subProbed.remove(playerID)
            subProbeInFlight.remove(playerID)
            apply(.playerRemoved(playerID: playerID))
            await stopSocket(playerID)
            if snapshot.players.isEmpty {
                apply(.status(.noPlayersFound))
            }
            if gatewayID == playerID { gatewayID = snapshot.players.first?.id }
            await reconcileSubscriptions()
        case .permissionDenied:
            logger.info("discovery reported Local Network permission denied")
            apply(.status(.localNetworkDenied))
        }
    }

    /// Starts (replacing any prior run, so there is never more than one loop) the loop that
    /// retries the initial topology fetch — and, once topology succeeds, the initial favorites
    /// fetch — until both succeed, topology comes back unauthorized/denied, or it's cancelled by
    /// `stop()`. On each failed topology attempt it fails the gateway over to another discovered
    /// player before backing off, so a single unreachable player doesn't block bootstrapping
    /// forever when another one might answer.
    private func startBootstrap() {
        bootstrapTask?.cancel()
        bootstrapTask = Task { [weak self, configuration] in
            var attempt = 0
            var favoritesLoaded = false
            while !Task.isCancelled {
                guard let self else { return }
                await self.refreshTopology()
                if Task.isCancelled { return }
                let checkpoint = await self.bootstrapCheckpoint()
                guard checkpoint.started else { return }
                switch checkpoint.status {
                case .unauthorized, .localNetworkDenied:
                    return
                case .ready:
                    if !favoritesLoaded {
                        favoritesLoaded = await self.refreshFavorites()
                    }
                    if favoritesLoaded { return }
                default:
                    // Topology itself failed; another discovered player might answer.
                    await self.rotateGateway()
                }
                if Task.isCancelled { return }
                try? await Task.sleep(for: configuration.backoff.delay(attempt: attempt, random: Double.random(in: 0...1)))
                attempt += 1
            }
        }
    }

    /// Cancels any running bootstrap loop and starts a fresh discovery timeout, so a bootstrap
    /// that fails again after a recovery attempt still eventually reports `.noPlayersFound`
    /// instead of leaving the UI stuck on `.discovering` forever.
    private func armDiscoveryTimeout() {
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self, configuration] in
            do {
                try await Task.sleep(for: configuration.discoveryTimeout)
            } catch {
                return
            }
            await self?.discoveryTimedOut()
        }
    }

    /// Snapshot of the state a running bootstrap loop needs to check after crossing back onto
    /// the actor, in one hop: whether `stop()` has run since, and the current status.
    private func bootstrapCheckpoint() -> (started: Bool, status: HouseholdStatus) {
        (started, snapshot.status)
    }

    /// Moves `gatewayID` to the next known, not-yet-removed player address (sorted ids, wrapping
    /// around), so a persistently-unreachable gateway doesn't block bootstrapping forever when
    /// another already-discovered player might answer.
    private func rotateGateway() {
        let candidates = addresses.keys.filter { !removedPlayers.contains($0) }.sorted()
        guard candidates.count > 1, let current = gatewayID,
              let currentIndex = candidates.firstIndex(of: current) else { return }
        let nextIndex = candidates.index(after: currentIndex)
        let next = candidates[nextIndex == candidates.endIndex ? candidates.startIndex : nextIndex]
        guard next != current else { return }
        logger.info("bootstrap failing over gateway from \(current, privacy: .public) to \(next, privacy: .public)")
        gatewayID = next
    }

    private func discoveryTimedOut() {
        if snapshot.status == .discovering {
            logger.info("discovery timed out before any topology could be fetched")
            apply(.status(.noPlayersFound))
        }
    }

    // MARK: REST refreshes

    private func refreshTopology() async {
        guard let gateway = gatewayAddress() else { return }
        logger.info("fetching topology from \(gateway, privacy: .public)")
        do {
            let response = try await api.groups(from: gateway)
            // `stop()` may have run while this request was in flight; don't resurrect sockets
            // or otherwise touch state for a Household that's no longer running.
            guard started, !Task.isCancelled else { return }
            allowTrust(forWirePlayers: response.players)
            let filtered = excludingRemovedPlayers(groups: response.groups, players: response.players)
            apply(.topology(groups: filtered.groups, players: filtered.players))
            for player in snapshot.players {
                addresses[player.id] = player.address
                trustStore?.allow(host: player.address)
            }
            // A late success arriving after Local Network access was denied must not paper over
            // that status with `.ready`.
            if snapshot.status != .ready && snapshot.status != .localNetworkDenied {
                apply(.status(.ready))
            }
            await ensureSockets()
            await reconcileSubscriptions()
            await probeSubs()
        } catch let error as LocalAPIError where error == .invalidAPIKey || error == .unauthorized {
            logger.error("topology fetch from \(gateway, privacy: .public) unauthorized: \(String(describing: error), privacy: .public)")
            apply(.status(.unauthorized))
        } catch {
            // Keep the previous snapshot; the bootstrap loop (before `.ready`) or the next
            // socket event/command (after) will retry.
            logger.error("topology fetch from \(gateway, privacy: .public) failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Fetches favorites once; returns whether it succeeded so the bootstrap loop can retry it
    /// alongside topology until both have loaded at least once.
    @discardableResult
    private func refreshFavorites() async -> Bool {
        guard let gateway = gatewayAddress() else { return false }
        do {
            let favorites = try await api.favorites(from: gateway)
            apply(.favorites(favorites))
            return true
        } catch {
            logger.error("favorites fetch from \(gateway, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    /// Only marks a player probed once the probe actually succeeds, so a timed-out or failed
    /// probe doesn't pin `hasSub = false` forever — the next topology change retries it.
    private func probeSubs() async {
        for player in snapshot.players where !subProbed.contains(player.id) && !subProbeInFlight.contains(player.id) {
            subProbeInFlight.insert(player.id)
            let result = try? await upnp.hasSub(address: player.address)
            subProbeInFlight.remove(player.id)
            guard let hasSub = result else { continue }
            subProbed.insert(player.id)
            apply(.playerHasSub(playerID: player.id, hasSub: hasSub))
        }
    }

    // MARK: Sockets

    private func ensureSockets() async {
        let wanted = Set(snapshot.players.map(\.id))
        for id in Set(sockets.keys).subtracting(wanted) {
            await stopSocket(id)
        }
        for player in snapshot.players where sockets[player.id] == nil && !player.address.isEmpty {
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
        let event: SocketEvent
        switch output {
        case .connected:
            logger.info("socket connected for player \(playerID, privacy: .public)")
            return
        case .disconnected:
            logger.info("socket disconnected for player \(playerID, privacy: .public)")
            return
        case .event(let socketEvent):
            event = socketEvent
        }
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
        let previousStatus = snapshot.status
        snapshot = SnapshotReducer.reduce(snapshot, event)
        let newStatus = snapshot.status
        if newStatus != previousStatus {
            logger.info("status changed from \(String(describing: previousStatus), privacy: .public) to \(String(describing: newStatus), privacy: .public)")
        }
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
