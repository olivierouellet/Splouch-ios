import Foundation

/// One open WebSocket. `receive()` throws once the connection is gone, which is
/// the only close signal the socket loop relies on.
public protocol WebSocketConnection: Sendable {
    func send(_ text: String) async throws
    func receive() async throws -> String
    func close() async
}

/// Opens connections. Resolves once the socket is actually open, or throws.
public protocol WebSocketConnector: Sendable {
    func open(_ url: URL) async throws -> any WebSocketConnection
}

/// `URLSessionWebSocketTask` behind the protocol above. `open` resolves on the
/// session delegate's open callback and throws on a completion that arrives
/// before it, so a refused or unreachable server fails fast.
public final class URLSessionWebSocketConnector: WebSocketConnector, @unchecked Sendable {
    private let session: URLSession
    private let delegate: OpenDelegate

    public init(configuration: URLSessionConfiguration = .default) {
        let delegate = OpenDelegate()
        self.delegate = delegate
        self.session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }

    public func open(_ url: URL) async throws -> any WebSocketConnection {
        let task = session.webSocketTask(with: url)
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, any Error>) in
            delegate.register(task, c)
            task.resume()
        }
        return URLSessionWebSocketConnection(task: task)
    }

    private final class OpenDelegate: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
        private let lock = NSLock()
        private var pending: [ObjectIdentifier: CheckedContinuation<Void, any Error>] = [:]

        func register(_ task: URLSessionWebSocketTask, _ c: CheckedContinuation<Void, any Error>) {
            lock.withLock { pending[ObjectIdentifier(task)] = c }
        }

        private func take(_ task: URLSessionTask) -> CheckedContinuation<Void, any Error>? {
            lock.withLock { pending.removeValue(forKey: ObjectIdentifier(task)) }
        }

        func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
            take(webSocketTask)?.resume()
        }

        func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
            take(webSocketTask)?.resume(throwing: URLError(.networkConnectionLost))
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
            take(task)?.resume(throwing: error ?? URLError(.cannotConnectToHost))
        }
    }
}

final class URLSessionWebSocketConnection: WebSocketConnection, @unchecked Sendable {
    private let task: URLSessionWebSocketTask

    init(task: URLSessionWebSocketTask) {
        self.task = task
    }

    func send(_ text: String) async throws {
        try await task.send(.string(text))
    }

    func receive() async throws -> String {
        switch try await task.receive() {
        case .string(let s): return s
        case .data(let d): return String(decoding: d, as: UTF8.self)
        @unknown default: return ""
        }
    }

    func close() async {
        task.cancel(with: .normalClosure, reason: nil)
    }
}
