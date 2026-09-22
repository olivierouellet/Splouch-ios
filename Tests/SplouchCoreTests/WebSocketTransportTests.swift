import Foundation
import Testing
@testable import SplouchCore

/// `URLSessionWebSocketConnector` is the one class the fakes cannot stand in
/// for: `FakeConnector` exists to replace it, and `StubServer` cannot reach it
/// because a `URLProtocol` answers with a body rather than a `101`. So these run
/// against a real server on loopback — see `LoopbackWebSocketServer`.
///
/// What is being checked is the contract `SplouchSocket` relies on and the fake
/// only promises: `open` resolves once the socket is actually open and throws
/// otherwise, and `receive` throws when the connection is gone, whichever way it
/// went.
@Suite(.serialized) struct WebSocketTransportTests {
    func server() async throws -> LoopbackWebSocketServer {
        let s = try LoopbackWebSocketServer()
        try await s.start()
        return s
    }

    func connector() -> URLSessionWebSocketConnector {
        URLSessionWebSocketConnector(configuration: .ephemeral)
    }

    @Test func opensOnlyOnceTheHandshakeHasCompleted() async throws {
        let server = try await self.server()
        defer { server.stop() }

        let conn = try await connector().open(server.url)
        // `open` resolved on the delegate's didOpen, so the upgrade is already
        // done by the time it returns — nothing to wait for here.
        #expect(server.handshakeCount == 1)
        #expect(server.isConnected)
        await conn.close()
    }

    /// C-01/C-02: what the socket loop sends has to arrive as a text frame the
    /// far end can read — masked, since a client must mask, and framed.
    @Test func textGoesOutAsAFrameTheServerCanRead() async throws {
        let server = try await self.server()
        defer { server.stop() }
        let conn = try await connector().open(server.url)

        try await conn.send(#"{"event":"join_meet","data":{"meet_id":"m1"}}"#)
        try await conn.send("second")
        #expect(await eventually { server.received.count == 2 })
        #expect(server.received[0] == #"{"event":"join_meet","data":{"meet_id":"m1"}}"#)
        #expect(server.received[1] == "second")
        await conn.close()
    }

    /// A payload past 125 bytes changes how the length is framed. The scoreboard
    /// frames are all past it, so this is the ordinary case, not the edge.
    @Test func aFrameLongerThanTheShortLengthSurvives() async throws {
        let server = try await self.server()
        defer { server.stop() }
        let conn = try await connector().open(server.url)

        let long = String(repeating: "lane", count: 200)   // 800 bytes
        try await conn.send(long)
        #expect(await eventually { server.received.count == 1 })
        #expect(server.received.first == long)
        await conn.close()
    }

    @Test func framesFromTheServerArriveInOrder() async throws {
        let server = try await self.server()
        defer { server.stop() }
        let conn = try await connector().open(server.url)

        server.push(#"{"event":"meet_live"}"#)
        server.push(#"{"event":"update_scoreboard"}"#)
        #expect(try await conn.receive() == #"{"event":"meet_live"}"#)
        #expect(try await conn.receive() == #"{"event":"update_scoreboard"}"#)
        await conn.close()
    }

    /// The client decodes a binary frame as text. No Splouch server sends one,
    /// but the branch exists and a proxy or a future server could.
    @Test func aBinaryFrameIsReadAsText() async throws {
        let server = try await self.server()
        defer { server.stop() }
        let conn = try await connector().open(server.url)

        server.pushBinary(Data(#"{"event":"reload"}"#.utf8))
        #expect(try await conn.receive() == #"{"event":"reload"}"#)
        await conn.close()
    }

    /// C-03: `receive()` throwing is the only close signal the socket loop has.
    /// A clean close from the server has to produce it.
    @Test func aCleanCloseFromTheServerMakesReceiveThrow() async throws {
        let server = try await self.server()
        defer { server.stop() }
        let conn = try await connector().open(server.url)

        server.closeFromServer()
        await #expect(throws: (any Error).self) { try await conn.receive() }
    }

    /// And so does a server that vanishes without one — a Pi losing power, which
    /// is the failure this app actually meets on a pool deck.
    @Test func aServerThatVanishesAlsoMakesReceiveThrow() async throws {
        let server = try await self.server()
        defer { server.stop() }
        let conn = try await connector().open(server.url)

        server.dropWithoutClosing()
        await #expect(throws: (any Error).self) { try await conn.receive() }
    }

    /// Closing from this end sends a close frame rather than just dropping, so
    /// the server can free the room instead of waiting for a timeout.
    @Test func closingTellsTheServer() async throws {
        let server = try await self.server()
        defer { server.stop() }
        let conn = try await connector().open(server.url)
        #expect(await eventually { server.handshakeCount == 1 })

        await conn.close()
        #expect(await eventually { server.sawClientClose })
    }

    /// P-13 and C-04: a server that is not there fails the open rather than
    /// hanging, which is what lets the picker say so and the loop back off.
    @Test func openThrowsWhenNothingIsListening() async throws {
        let server = try await self.server()
        let dead = server.url
        server.stop()
        // The port is free again; nothing will answer the upgrade.
        await #expect(throws: (any Error).self) { try await connector().open(dead) }
    }

    /// Two sockets against one server are independent, which is the shape a meet
    /// actually opens in: scoreboard, results and schedule at once.
    @Test func severalSocketsShareAServerWithoutSharingState() async throws {
        let server = try await self.server()
        defer { server.stop() }
        let c = connector()
        let a = try await c.open(server.url)
        let b = try await c.open(server.url)

        try await a.send("from-a")
        try await b.send("from-b")
        #expect(await eventually { server.received.count == 2 })
        #expect(Set(server.received) == ["from-a", "from-b"])
        #expect(server.handshakeCount == 2)
        await a.close()
        await b.close()
    }
}
