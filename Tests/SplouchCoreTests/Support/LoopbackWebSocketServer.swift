import CryptoKit
import Foundation
import Network

/// A real WebSocket server on 127.0.0.1, for the one class the fakes cannot
/// stand in for.
///
/// `FakeConnector` replaces `URLSessionWebSocketConnector`, so it can never test
/// it; and `StubServer` cannot either, because a `URLProtocol` is handed the
/// request but answers with a body rather than a `101`, and a WebSocket needs a
/// duplex frame channel rather than a response. What is left is a server, so
/// this is one: an `NWListener` on an ephemeral loopback port that performs the
/// RFC 6455 handshake and speaks enough of the framing to be talked to.
///
/// Deliberately minimal. It accepts one client at a time, keeps every frame it
/// is sent, and can push, ping and close. It is not a WebSocket implementation —
/// it is the other end of one, sized for these tests.
final class LoopbackWebSocketServer: @unchecked Sendable {
    private let listener: NWListener
    private let lock = NSLock()
    private var clients: [NWConnection] = []
    private var buffers: [ObjectIdentifier: Data] = [:]
    private var textFrames: [String] = []
    private var handshakes = 0
    private var closedByClient = false

    /// The port the OS picked, once `start()` has returned.
    private(set) var port: UInt16 = 0

    /// Every text frame a client has sent, in order.
    var received: [String] { lock.withLock { textFrames } }
    /// How many clients completed the handshake.
    var handshakeCount: Int { lock.withLock { handshakes } }
    /// Whether a client sent a close frame.
    var sawClientClose: Bool { lock.withLock { closedByClient } }
    var isConnected: Bool { lock.withLock { !clients.isEmpty } }

    init() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        listener = try NWListener(using: params, on: .any)
    }

    /// Starts listening and resolves once the port is known.
    func start() async throws {
        let ready = Ready()
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready: ready.fire(nil)
            case .failed(let e): ready.fire(e)
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
        listener.start(queue: .global(qos: .userInitiated))
        try await ready.wait()
        port = listener.port?.rawValue ?? 0
    }

    func stop() {
        let open: [NWConnection] = lock.withLock {
            let c = clients
            clients = []
            return c
        }
        for c in open { c.cancel() }
        listener.cancel()
    }

    var url: URL { URL(string: "ws://127.0.0.1:\(port)/ws/scoreboard")! }

    // MARK: - Speaking to the client

    /// Sends one text frame, unmasked as a server must.
    func push(_ text: String) {
        send(frame(opcode: 0x1, payload: Data(text.utf8)))
    }

    /// Sends one binary frame. The reference server never does, but the client
    /// decodes one, so the branch has to be reachable.
    func pushBinary(_ data: Data) {
        send(frame(opcode: 0x2, payload: data))
    }

    /// Sends a ping, which `URLSessionWebSocketTask` answers on its own.
    func ping() {
        send(frame(opcode: 0x9, payload: Data()))
    }

    /// A clean close: the client's pending `receive()` throws.
    func closeFromServer() {
        var payload = Data([0x03, 0xE8])   // 1000, normal closure
        payload.append(contentsOf: Array("bye".utf8))
        send(frame(opcode: 0x8, payload: payload))
    }

    /// The rude version — the socket disappears with no close frame, which is
    /// what a Pi losing power looks like from the phone.
    func dropWithoutClosing() {
        let open: [NWConnection] = lock.withLock {
            let c = clients
            clients = []
            return c
        }
        for c in open { c.forceCancel() }
    }

    private func send(_ data: Data) {
        let open = lock.withLock { clients }
        for c in open { c.send(content: data, completion: .contentProcessed { _ in }) }
    }

    // MARK: - Connection lifecycle

    private func accept(_ conn: NWConnection) {
        lock.withLock { clients.append(conn) }
        conn.stateUpdateHandler = { [weak self] state in
            if case .cancelled = state { self?.forget(conn) }
            if case .failed = state { self?.forget(conn) }
        }
        conn.start(queue: .global(qos: .userInitiated))
        read(conn, handshakeDone: false)
    }

    private func forget(_ conn: NWConnection) {
        lock.withLock { clients.removeAll { $0 === conn } }
    }

    private func read(_ conn: NWConnection, handshakeDone: Bool) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                var done = handshakeDone
                self.lock.withLock {
                    self.buffers[ObjectIdentifier(conn), default: Data()].append(data)
                }
                if !done { done = self.tryHandshake(conn) }
                if done { self.drainFrames(conn) }
                if error == nil, !isComplete {
                    self.read(conn, handshakeDone: done)
                    return
                }
            }
            if error != nil || isComplete { self.forget(conn) ; return }
            self.read(conn, handshakeDone: handshakeDone)
        }
    }

    /// Answers the upgrade once the request headers are all in. Returns true
    /// when the handshake has been completed (now or earlier).
    private func tryHandshake(_ conn: NWConnection) -> Bool {
        let key: String? = lock.withLock {
            let id = ObjectIdentifier(conn)
            guard let buf = buffers[id],
                  let text = String(data: buf, encoding: .utf8),
                  let headerEnd = text.range(of: "\r\n\r\n") else { return nil }
            let head = String(text[text.startIndex..<headerEnd.lowerBound])
            buffers[id] = buf.dropFirst(head.utf8.count + 4)
            for line in head.split(separator: "\r\n") {
                let parts = line.split(separator: ":", maxSplits: 1)
                guard parts.count == 2,
                      parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "sec-websocket-key"
                else { continue }
                return parts[1].trimmingCharacters(in: .whitespaces)
            }
            return nil
        }
        guard let key else { return false }

        let magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        let digest = Insecure.SHA1.hash(data: Data((key + magic).utf8))
        let accept = Data(digest).base64EncodedString()
        let response = """
        HTTP/1.1 101 Switching Protocols\r
        Upgrade: websocket\r
        Connection: Upgrade\r
        Sec-WebSocket-Accept: \(accept)\r
        \r

        """
        conn.send(content: Data(response.utf8), completion: .contentProcessed { _ in })
        lock.withLock { handshakes += 1 }
        return true
    }

    // MARK: - Framing (RFC 6455 §5)

    /// Pulls every whole frame out of the buffer. A client always masks.
    private func drainFrames(_ conn: NWConnection) {
        let id = ObjectIdentifier(conn)
        while true {
            let action: (() -> Void)? = lock.withLock {
                guard var buf = buffers[id], buf.count >= 2 else { return nil }
                let bytes = [UInt8](buf)
                let opcode = bytes[0] & 0x0F
                let masked = bytes[1] & 0x80 != 0
                var len = Int(bytes[1] & 0x7F)
                var offset = 2
                if len == 126 {
                    guard bytes.count >= 4 else { return nil }
                    len = Int(bytes[2]) << 8 | Int(bytes[3])
                    offset = 4
                } else if len == 127 {
                    guard bytes.count >= 10 else { return nil }
                    len = (2..<10).reduce(0) { $0 << 8 | Int(bytes[$1]) }
                    offset = 10
                }
                var mask: [UInt8] = []
                if masked {
                    guard bytes.count >= offset + 4 else { return nil }
                    mask = Array(bytes[offset..<(offset + 4)])
                    offset += 4
                }
                guard bytes.count >= offset + len else { return nil }
                var payload = Array(bytes[offset..<(offset + len)])
                if masked {
                    for i in payload.indices { payload[i] ^= mask[i % 4] }
                }
                buf = Data(bytes.dropFirst(offset + len))
                buffers[id] = buf

                switch opcode {
                case 0x1, 0x2:
                    let text = String(decoding: payload, as: UTF8.self)
                    textFrames.append(text)
                case 0x8:
                    closedByClient = true
                    return { conn.cancel() }
                case 0x9:
                    let pong = self.frame(opcode: 0xA, payload: Data(payload))
                    return { conn.send(content: pong, completion: .contentProcessed { _ in }) }
                default:
                    break
                }
                return {}
            }
            guard let action else { return }
            action()
        }
    }

    /// A server frame: FIN set, never masked.
    private func frame(opcode: UInt8, payload: Data) -> Data {
        var out = Data([0x80 | opcode])
        if payload.count < 126 {
            out.append(UInt8(payload.count))
        } else {
            out.append(126)
            out.append(UInt8(payload.count >> 8))
            out.append(UInt8(payload.count & 0xFF))
        }
        out.append(payload)
        return out
    }

    /// One-shot "the listener is up", bridged to async.
    private final class Ready: @unchecked Sendable {
        private let lock = NSLock()
        private var result: Result<Void, any Error>?
        private var waiter: CheckedContinuation<Void, any Error>?

        func fire(_ error: (any Error)?) {
            let c: CheckedContinuation<Void, any Error>? = lock.withLock {
                guard result == nil else { return nil }
                result = error.map { .failure($0) } ?? .success(())
                let w = waiter
                waiter = nil
                return w
            }
            if let c { resume(c) }
        }

        func wait() async throws {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, any Error>) in
                let ready = lock.withLock { result != nil }
                if ready { resume(c) } else { lock.withLock { waiter = c } }
            }
        }

        private func resume(_ c: CheckedContinuation<Void, any Error>) {
            switch lock.withLock({ result }) {
            case .success, .none: c.resume()
            case .failure(let e): c.resume(throwing: e)
            }
        }
    }
}
