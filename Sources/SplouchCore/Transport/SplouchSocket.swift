import Foundation

/// The intervals of app.md §6. Tests shrink them; the app uses `.standard`.
public struct SocketTiming: Sendable, Equatable {
    /// C-04: send `ping` this often while open.
    public var heartbeat: Duration
    /// C-04: no inbound frame for this long means dead.
    public var stale: Duration
    /// C-05: a foreground probe with no `pong` within this window means dead.
    public var probe: Duration
    /// C-03: capped exponential backoff.
    public var backoffMin: Duration
    public var backoffMax: Duration

    public init(heartbeat: Duration = .seconds(15), stale: Duration = .seconds(35),
                probe: Duration = .seconds(4), backoffMin: Duration = .milliseconds(500),
                backoffMax: Duration = .seconds(5)) {
        self.heartbeat = heartbeat
        self.stale = stale
        self.probe = probe
        self.backoffMin = backoffMin
        self.backoffMax = backoffMax
    }

    public static let standard = SocketTiming()
}

public enum SocketEvent: Sendable, Equatable {
    /// The socket opened and the join frame, if any, was sent.
    case connected
    /// The socket dropped. Implies `meet_live = false` (C-09).
    case disconnected
    /// Any inbound frame except `pong`. Unknown events are passed through for
    /// the consumer to ignore (C-07).
    case frame(Frame)
}

/// One reconnecting WebSocket, the loop in app.md §6 — the same rules the
/// reference `ws.js` follows, one instance per path (C-01).
///
/// - `join` is sent on every connect, including every reconnect (C-02). On a
///   Pi it is nil: the Pi pushes on connect and has no rooms (api.md §2).
/// - Frames sent while disconnected are queued and flushed on connect (C-06).
/// - `wake()` is the foreground / network-restored probe (C-05). iOS freezes a
///   background socket without a close, so backoff alone never fires; this is
///   what makes the reconnect happen.
public actor SplouchSocket {
    public nonisolated let events: AsyncStream<SocketEvent>
    private let continuation: AsyncStream<SocketEvent>.Continuation

    public let url: URL
    private let connector: any WebSocketConnector
    private let timing: SocketTiming
    /// Re-sent on every connect. Settable so a session can change meets.
    public var join: Frame?

    private var connection: (any WebSocketConnection)?
    private var generation = 0
    private var runTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var probeTask: Task<Void, Never>?
    private var delay: Duration
    private var lastReceived: ContinuousClock.Instant = .now
    private var queue: [String] = []
    private var closed = false

    public init(url: URL, connector: any WebSocketConnector, join: Frame? = nil,
                timing: SocketTiming = .standard) {
        let (stream, cont) = AsyncStream<SocketEvent>.makeStream(bufferingPolicy: .unbounded)
        self.events = stream
        self.continuation = cont
        self.url = url
        self.connector = connector
        self.join = join
        self.timing = timing
        self.delay = timing.backoffMin
    }

    public var isConnected: Bool { connection != nil }

    public func setJoin(_ frame: Frame?) { join = frame }

    /// Opens the socket. Safe to call more than once.
    public func start() {
        guard !closed else { return }
        connect()
    }

    /// Stops for good: no reconnect, the event stream ends.
    public func close() async {
        closed = true
        reconnectTask?.cancel(); reconnectTask = nil
        probeTask?.cancel(); probeTask = nil
        stopHeartbeat()
        if let c = connection { await c.close() }
        runTask?.cancel()
        continuation.finish()
    }

    /// Sends now, or queues until the next connect (C-06).
    public func send(_ frame: Frame) async {
        guard let text = try? frame.encoded() else { return }
        if let c = connection {
            try? await c.send(text)
        } else {
            queue.append(text)
        }
    }

    /// C-05. Open: probe with a `ping` and close if nothing arrives within the
    /// probe window. Closed and idle: reconnect at once with the backoff reset.
    /// Connecting or already waiting on a probe: nothing to do.
    public func wake() {
        guard !closed else { return }
        if let c = connection {
            guard probeTask == nil else { return }
            let mark = lastReceived
            let gen = generation
            let window = timing.probe
            probeTask = Task {
                try? await c.send(Self.pingText)
                try? await Task.sleep(for: window)
                await self.probeExpired(mark: mark, generation: gen)
            }
        } else if runTask == nil {
            delay = timing.backoffMin
            connect()
        }
    }

    private func probeExpired(mark: ContinuousClock.Instant, generation gen: Int) async {
        probeTask = nil
        guard gen == generation, let c = connection, lastReceived == mark else { return }
        await c.close()
    }

    // MARK: - Loop

    private static let pingText = (try? Frame.ping.encoded()) ?? #"{"event":"ping"}"#

    private func connect() {
        reconnectTask?.cancel(); reconnectTask = nil
        guard runTask == nil, !closed else { return }
        runTask = Task { await self.run() }
    }

    private func run() async {
        let conn: any WebSocketConnection
        do {
            conn = try await connector.open(url)
        } catch {
            runTask = nil
            scheduleReconnect()
            return
        }
        if closed {
            await conn.close()
            runTask = nil
            return
        }
        generation += 1
        connection = conn
        delay = timing.backoffMin
        lastReceived = .now
        let pending = queue
        queue = []
        for text in pending { try? await conn.send(text) }
        if let join, let text = try? join.encoded() { try? await conn.send(text) }
        startHeartbeat()
        continuation.yield(.connected)

        while !Task.isCancelled {
            do {
                let text = try await conn.receive()
                lastReceived = .now
                guard let frame = try? Frame.decode(text) else { continue }
                if frame.event == "pong" { continue }   // liveness only
                continuation.yield(.frame(frame))
            } catch {
                break
            }
        }

        stopHeartbeat()
        probeTask?.cancel(); probeTask = nil
        connection = nil
        runTask = nil
        continuation.yield(.disconnected)
        if !closed { scheduleReconnect() }
    }

    private func scheduleReconnect() {
        guard !closed, reconnectTask == nil else { return }
        let wait = delay
        delay = min(delay * 2, timing.backoffMax)
        reconnectTask = Task {
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled else { return }
            self.reconnectFired()
        }
    }

    private func reconnectFired() {
        reconnectTask = nil
        connect()
    }

    private func startHeartbeat() {
        stopHeartbeat()
        let gen = generation
        let every = timing.heartbeat
        heartbeatTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: every)
                if Task.isCancelled { return }
                await self.heartbeatTick(generation: gen)
            }
        }
    }

    private func stopHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
    }

    private func heartbeatTick(generation gen: Int) async {
        guard gen == generation, let c = connection else { return }
        if .now - lastReceived > timing.stale {
            await c.close()   // silently dead: the loop ends and reconnects
            return
        }
        try? await c.send(Self.pingText)
    }
}
