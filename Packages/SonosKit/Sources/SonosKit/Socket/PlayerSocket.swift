import Foundation

/// One websocket to one player. Reconnects forever with backoff until `stop()`.
/// Subscriptions are re-sent on every (re)connect.
actor PlayerSocket {
    enum Output: Hashable, Sendable {
        case connected
        case disconnected
        case event(SocketEvent)
    }

    static let subprotocol = "v1.api.smartspeaker.audio"
    static let pingInterval: Duration = .seconds(30)

    let playerID: String
    let url: URL
    nonisolated let outputs: AsyncStream<Output>

    private let transport: any Transport
    private let backoff: Backoff
    private let continuation: AsyncStream<Output>.Continuation
    private var desired: Set<Subscription> = []
    private var active: Set<Subscription> = []
    private var connection: (any SocketConnection)?
    private var runTask: Task<Void, Never>?
    private var stopped = false

    init(playerID: String, address: String, transport: any Transport, backoff: Backoff = Backoff()) {
        self.playerID = playerID
        self.url = URL(string: "wss://\(address):\(LocalAPIClient.port)/websocket/api")!
        self.transport = transport
        self.backoff = backoff
        (outputs, continuation) = AsyncStream<Output>.makeStream()
    }

    func start() {
        guard runTask == nil, !stopped else { return }
        runTask = Task { await run() }
    }

    func stop() {
        stopped = true
        runTask?.cancel()
        runTask = nil
        connection?.close()
        connection = nil
        continuation.yield(.disconnected)
        continuation.finish()
    }

    func setSubscriptions(_ new: Set<Subscription>) async {
        desired = new
        guard let connection else { return }
        await reconcile(with: connection)
    }

    /// Sends the un/subscribe diff between `active` and `desired` on `connection`.
    /// `active` is updated to `desired` before any send so a `setSubscriptions` call that
    /// lands while this is awaiting a send always computes its own diff against the latest
    /// baseline, instead of one this call is still in the middle of publishing.
    private func reconcile(with connection: any SocketConnection) async {
        let toRemove = active.subtracting(desired)
        let toAdd = desired.subtracting(active)
        active = desired
        for subscription in toRemove {
            try? await connection.send(subscription.frame(command: "unsubscribe"))
        }
        for subscription in toAdd {
            try? await connection.send(subscription.frame(command: "subscribe"))
        }
    }

    private func run() async {
        var attempt = 0
        while !Task.isCancelled && !stopped {
            var pinger: Task<Void, Never>?
            do {
                let connection = try await transport.openSocket(
                    url,
                    headers: ["X-Sonos-Api-Key": LocalAPIClient.apiKey],
                    protocols: [Self.subprotocol]
                )
                // Snapshot `desired` and send the initial subscribes *before* publishing
                // `self.connection`, so a concurrent `setSubscriptions` sees no connection
                // yet (and only updates `desired`) rather than reconciling against a stale
                // `active` baseline. `reconcile` below then catches up on anything that
                // changed while these sends were in flight.
                let snapshot = desired
                do {
                    for subscription in snapshot {
                        try await connection.send(subscription.frame(command: "subscribe"))
                    }
                } catch {
                    connection.close()
                    throw error
                }
                self.connection = connection
                active = snapshot
                await reconcile(with: connection)
                attempt = 0
                continuation.yield(.connected)
                pinger = Task {
                    while !Task.isCancelled {
                        try? await Task.sleep(for: Self.pingInterval)
                        if Task.isCancelled { break }
                        try? await connection.ping()
                    }
                }
                for try await data in connection.messages() {
                    if let event = try? SocketFrameDecoder.decode(data) {
                        continuation.yield(.event(event))
                    }
                }
            } catch {
                // fall through to reconnect
            }
            pinger?.cancel()
            connection = nil
            active = []
            if stopped || Task.isCancelled { return }
            continuation.yield(.disconnected)
            try? await Task.sleep(for: backoff.delay(attempt: attempt, random: Double.random(in: 0...1)))
            attempt += 1
        }
    }
}
