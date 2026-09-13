import Foundation
@testable import SplouchCore

/// A scripted server end of one WebSocket.
final class FakeConnection: WebSocketConnection, @unchecked Sendable {
    private let lock = NSLock()
    private var sentFrames: [String] = []
    private var pending: [String] = []
    private var waiter: CheckedContinuation<String, any Error>?
    private var closed = false

    var sent: [String] { lock.withLock { sentFrames } }
    var sentEvents: [String] { sent.compactMap { try? Frame.decode($0).event } }
    var isClosed: Bool { lock.withLock { closed } }

    func send(_ text: String) async throws {
        try record(text)
    }

    private func record(_ text: String) throws {
        try lock.withLock {
            if closed { throw URLError(.networkConnectionLost) }
            sentFrames.append(text)
        }
    }

    func receive() async throws -> String {
        try await withCheckedThrowingContinuation { c in
            arm(c)
        }
    }

    private func arm(_ c: CheckedContinuation<String, any Error>) {
        let action: () -> Void = lock.withLock {
            if closed { return { c.resume(throwing: URLError(.networkConnectionLost)) } }
            if !pending.isEmpty {
                let t = pending.removeFirst()
                return { c.resume(returning: t) }
            }
            waiter = c
            return {}
        }
        action()
    }

    func close() async {
        closeNow()
    }

    private func closeNow() {
        let w: CheckedContinuation<String, any Error>? = lock.withLock {
            closed = true
            let w = waiter
            waiter = nil
            return w
        }
        w?.resume(throwing: URLError(.networkConnectionLost))
    }

    /// The server sends a frame.
    func push(_ text: String) {
        let w: CheckedContinuation<String, any Error>? = lock.withLock {
            if let w = waiter { waiter = nil; return w }
            pending.append(text)
            return nil
        }
        w?.resume(returning: text)
    }

    func push(_ frame: Frame) { push(try! frame.encoded()) }

    /// The server drops the connection.
    func dropFromServer() async { closeNow() }
}

final class FakeConnector: WebSocketConnector, @unchecked Sendable {
    private let lock = NSLock()
    private var opened: [FakeConnection] = []
    private var failures = 0
    private var attemptCount = 0
    private var times: [ContinuousClock.Instant] = []

    var connections: [FakeConnection] { lock.withLock { opened } }
    var latest: FakeConnection? { connections.last }
    var openCount: Int { lock.withLock { opened.count } }
    var attempts: Int { lock.withLock { attemptCount } }
    var attemptTimes: [ContinuousClock.Instant] { lock.withLock { times } }

    /// Make the next `n` opens fail.
    func failNextOpens(_ n: Int) { lock.withLock { failures = n } }

    func open(_ url: URL) async throws -> any WebSocketConnection {
        try attempt()
    }

    private func attempt() throws -> any WebSocketConnection {
        try lock.withLock {
            attemptCount += 1
            times.append(.now)
            if failures > 0 { failures -= 1; throw URLError(.cannotConnectToHost) }
            let c = FakeConnection()
            opened.append(c)
            return c
        }
    }
}

/// Collects a socket's events so tests can poll without blocking on the stream.
actor EventRecorder {
    private(set) var events: [SocketEvent] = []

    init(_ stream: AsyncStream<SocketEvent>) {
        Task { [weak self] in
            for await e in stream { await self?.append(e) }
        }
    }

    private func append(_ e: SocketEvent) { events.append(e) }

    func count(_ match: (SocketEvent) -> Bool) -> Int { events.filter(match).count }
}

/// Polls until `condition` holds or `timeout` passes. Returns whether it held.
func eventually(_ timeout: Duration = .seconds(3), _ condition: @Sendable () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return await condition()
}
