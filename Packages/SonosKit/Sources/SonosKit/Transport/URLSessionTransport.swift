import Foundation

public final class URLSessionTransport: Transport, @unchecked Sendable {
    public let trustStore: TrustStore
    private let session: URLSession

    public init(trustStore: TrustStore = TrustStore()) {
        self.trustStore = trustStore
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.httpShouldUsePipelining = false
        session = URLSession(configuration: configuration, delegate: TrustDelegate(store: trustStore), delegateQueue: nil)
    }

    public func send(_ request: APIRequest) async throws -> APIResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        let (data, response) = try await session.data(for: urlRequest)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return APIResponse(status: status, body: data)
    }

    public func openSocket(_ url: URL, headers: [String: String], protocols: [String]) async throws -> any SocketConnection {
        var request = URLRequest(url: url)
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.setValue(protocols.joined(separator: ", "), forHTTPHeaderField: "Sec-WebSocket-Protocol")
        let task = session.webSocketTask(with: request)
        task.resume()
        return URLSessionSocketConnection(task: task)
    }
}

/// Accepts the player's self-signed certificate only for allowed private hosts.
private final class TrustDelegate: NSObject, URLSessionDelegate, Sendable {
    let store: TrustStore

    init(store: TrustStore) {
        self.store = store
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let space = challenge.protectionSpace
        guard space.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = space.serverTrust,
              store.shouldTrust(host: space.host) else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}

private final class URLSessionSocketConnection: SocketConnection, @unchecked Sendable {
    private let task: URLSessionWebSocketTask

    init(task: URLSessionWebSocketTask) {
        self.task = task
    }

    func send(_ data: Data) async throws {
        try await task.send(.string(String(decoding: data, as: UTF8.self)))
    }

    func messages() -> AsyncThrowingStream<Data, any Error> {
        let task = self.task
        return AsyncThrowingStream { continuation in
            let receiver = Task {
                do {
                    while !Task.isCancelled {
                        switch try await task.receive() {
                        case .string(let text): continuation.yield(Data(text.utf8))
                        case .data(let data): continuation.yield(data)
                        @unknown default: break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in receiver.cancel() }
        }
    }

    func ping() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            task.sendPing { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }

    func close() {
        task.cancel(with: .normalClosure, reason: nil)
    }
}
