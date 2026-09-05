import Foundation

public struct APIRequest: Sendable, Hashable {
    public var method: String
    public var url: URL
    public var headers: [String: String]
    public var body: Data?

    public init(method: String, url: URL, headers: [String: String] = [:], body: Data? = nil) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
    }
}

public struct APIResponse: Sendable {
    public var status: Int
    public var body: Data

    public init(status: Int, body: Data) {
        self.status = status
        self.body = body
    }
}

/// One open websocket. `messages()` ends (or throws) when the connection drops.
public protocol SocketConnection: Sendable {
    func send(_ data: Data) async throws
    func messages() -> AsyncThrowingStream<Data, any Error>
    func ping() async throws
    func close()
}

/// Everything that touches the network goes through this so tests can fake it.
public protocol Transport: Sendable {
    func send(_ request: APIRequest) async throws -> APIResponse
    func openSocket(_ url: URL, headers: [String: String], protocols: [String]) async throws -> any SocketConnection
}
