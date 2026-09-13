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

/// `URLSessionWebSocketTask` behind the protocol above.
///
/// `open` confirms the handshake with a protocol-level ping (not the app-level
/// `{"event":"ping"}` frame): its completion fires on the pong or on the
/// connection error, so no delegate is needed to learn that the socket opened.
public struct URLSessionWebSocketConnector: WebSocketConnector {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func open(_ url: URL) async throws -> any WebSocketConnection {
        let task = session.webSocketTask(with: url)
        task.resume()
        do {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, any Error>) in
                task.sendPing { error in
                    if let error { c.resume(throwing: error) } else { c.resume() }
                }
            }
        } catch {
            task.cancel(with: .abnormalClosure, reason: nil)
            throw error
        }
        return URLSessionWebSocketConnection(task: task)
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
