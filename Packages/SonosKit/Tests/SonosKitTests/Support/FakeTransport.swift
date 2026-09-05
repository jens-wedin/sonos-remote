import Foundation
import Synchronization
@testable import SonosKit

struct StubResponse: Sendable {
    var status: Int = 200
    var body: Data = Data("{}".utf8)
}

/// Records every request, answers from stubs matched by URL fragment (last registered wins),
/// and hands out FakeSocketConnections that tests can push frames into.
final class FakeTransport: Transport, Sendable {
    private struct Rule: Sendable {
        var fragment: String
        var sequence: [StubResponse]
        var index: Int = 0
    }

    private struct State: Sendable {
        var requests: [APIRequest] = []
        var rules: [Rule] = []
        var sockets: [FakeSocketConnection] = []
        var onSocketOpened: (@Sendable (FakeSocketConnection) -> Void)?
    }

    private let state = Mutex(State())

    var requests: [APIRequest] { state.withLock { $0.requests } }
    var sockets: [FakeSocketConnection] { state.withLock { $0.sockets } }
    var socketCount: Int { sockets.count }

    /// Test hook: invoked synchronously, before `openSocket` returns, on every connection it
    /// creates from here on. Opt-in; nil by default so existing tests are unaffected. Lets a
    /// test arrange a connection's state (e.g. `blockSends()`) before `PlayerSocket` can send
    /// on it, closing races that would otherwise depend on scheduling.
    func onSocketOpened(_ hook: @escaping @Sendable (FakeSocketConnection) -> Void) {
        state.withLock { $0.onSocketOpened = hook }
    }

    func requests(matching fragment: String) -> [APIRequest] {
        requests.filter { $0.url.absoluteString.contains(fragment) }
    }

    func socket(forHost host: String) -> FakeSocketConnection? {
        sockets.last { $0.url.host() == host }
    }

    func respond(whenPathContains fragment: String, status: Int = 200, body: Data = Data("{}".utf8)) {
        respond(whenPathContains: fragment, sequence: [StubResponse(status: status, body: body)])
    }

    /// Answers in order; the last stub repeats forever.
    func respond(whenPathContains fragment: String, sequence: [StubResponse]) {
        state.withLock { $0.rules.append(Rule(fragment: fragment, sequence: sequence)) }
    }

    func send(_ request: APIRequest) async throws -> APIResponse {
        let stub: StubResponse = state.withLock { state in
            state.requests.append(request)
            guard let ruleIndex = state.rules.lastIndex(where: { request.url.absoluteString.contains($0.fragment) }) else {
                return StubResponse()
            }
            var rule = state.rules[ruleIndex]
            let response = rule.sequence[min(rule.index, rule.sequence.count - 1)]
            rule.index += 1
            state.rules[ruleIndex] = rule
            return response
        }
        return APIResponse(status: stub.status, body: stub.body)
    }

    func openSocket(_ url: URL, headers: [String: String], protocols: [String]) async throws -> any SocketConnection {
        let connection = FakeSocketConnection(url: url)
        let hook = state.withLock { state -> (@Sendable (FakeSocketConnection) -> Void)? in
            state.sockets.append(connection)
            return state.onSocketOpened
        }
        hook?(connection)
        return connection
    }
}
