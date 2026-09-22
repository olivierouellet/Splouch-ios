import Foundation
import Testing
@testable import SplouchCore

@Suite(.serialized) struct SplouchSocketTests {
    let url = URL(string: "wss://example.test/ws/scoreboard")!
    let timing = SocketTiming(heartbeat: .milliseconds(40), stale: .milliseconds(100),
                              probe: .milliseconds(40), backoffMin: .milliseconds(10),
                              backoffMax: .milliseconds(40))
    let join = Frame.joinMeet(meetID: "m1", vid: "v1")

    func make(join: Frame? = nil) -> (SplouchSocket, FakeConnector, EventRecorder) {
        let connector = FakeConnector()
        let socket = SplouchSocket(url: url, connector: connector, join: join, timing: timing)
        let recorder = EventRecorder(socket.events)
        return (socket, connector, recorder)
    }

    func isFrame(_ e: SocketEvent, _ event: String) -> Bool {
        if case .frame(let f) = e { return f.event == event }
        return false
    }

    // C-02, C-06

    @Test func joinIsSentOnConnectAfterQueuedFrames() async {
        let (socket, connector, recorder) = make(join: join)
        await socket.send(Frame(event: "early", data: .object(["a": .number(1)])))
        await socket.start()
        #expect(await eventually { await recorder.events.contains(.connected) })
        let conn = connector.latest!
        #expect(conn.sentEvents == ["early", "join_meet"])
        #expect(await socket.isConnected)
        await socket.close()
    }

    @Test func noJoinOnAPi() async {
        let (socket, connector, recorder) = make(join: nil)
        await socket.start()
        #expect(await eventually { await recorder.events.contains(.connected) })
        #expect(connector.latest!.sentEvents.isEmpty)
        await socket.close()
    }

    // C-07 plus pong swallowing

    @Test func framesSurfaceAndPongDoesNot() async {
        let (socket, connector, recorder) = make(join: join)
        await socket.start()
        #expect(await eventually { await recorder.events.contains(.connected) })
        let conn = connector.latest!
        conn.push(Frame(event: "pong"))
        conn.push(Frame(event: "meet_live", data: .object(["live": .bool(true)])))
        conn.push(Frame(event: "something_new", data: .string("x")))
        conn.push("not json at all")
        #expect(await eventually { await recorder.count { isFrame($0, "something_new") } == 1 })
        let events = await recorder.events
        #expect(events.contains(.frame(Frame(event: "meet_live", data: .object(["live": .bool(true)])))))
        #expect(!events.contains { isFrame($0, "pong") })
        await socket.close()
    }

    // C-03 and C-02 on reconnect

    @Test func serverDropReconnectsAndRejoins() async {
        let (socket, connector, recorder) = make(join: join)
        await socket.start()
        #expect(await eventually { await recorder.events.contains(.connected) })
        let first = connector.latest!
        await first.dropFromServer()
        #expect(await eventually { await recorder.events.contains(.disconnected) })
        #expect(await eventually { connector.openCount == 2 })
        #expect(await eventually { connector.latest!.sentEvents == ["join_meet"] })
        #expect(await eventually { await recorder.count { $0 == .connected } == 2 })
        await socket.close()
    }

    @Test func backoffDoublesToTheCapAndResetsOnConnect() async {
        let (socket, connector, recorder) = make(join: join)
        connector.failNextOpens(4)
        await socket.start()
        #expect(await eventually(.seconds(5)) { await recorder.events.contains(.connected) })
        #expect(connector.attempts == 5)
        let gaps = zip(connector.attemptTimes.dropFirst(), connector.attemptTimes).map { $0 - $1 }
        // 10, 20, 40, 40 ms nominal; timers only ever run late.
        #expect(gaps[0] >= .milliseconds(10))
        #expect(gaps[1] >= .milliseconds(20))
        #expect(gaps[2] >= .milliseconds(40))
        #expect(gaps[3] >= .milliseconds(40))
        #expect(gaps[3] < .milliseconds(80) * 3)
        // A successful connect resets the delay: the next drop reconnects fast.
        await connector.latest!.dropFromServer()
        let before = ContinuousClock.now
        #expect(await eventually { connector.attempts == 6 })
        #expect(ContinuousClock.now - before < .milliseconds(40) * 3)
        await socket.close()
    }

    // C-04

    @Test func heartbeatPingsWhileOpen() async {
        let (socket, connector, recorder) = make(join: join)
        await socket.start()
        #expect(await eventually { await recorder.events.contains(.connected) })
        let conn = connector.latest!
        // Keep it alive by answering.
        let pump = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(20))
                conn.push(Frame(event: "pong"))
            }
        }
        #expect(await eventually { conn.sentEvents.filter { $0 == "ping" }.count >= 2 })
        pump.cancel()
        #expect(connector.openCount == 1)
        await socket.close()
    }

    @Test func silenceBeyondStaleClosesAndReconnects() async {
        let (socket, connector, recorder) = make(join: join)
        await socket.start()
        #expect(await eventually { await recorder.events.contains(.connected) })
        let first = connector.latest!
        // Nothing inbound: pings go unanswered, the watchdog closes it.
        #expect(await eventually { first.isClosed })
        #expect(await eventually { connector.openCount == 2 })
        #expect(await eventually { connector.latest!.sentEvents.first == "join_meet" })
        await socket.close()
    }

    // C-05

    @Test func wakeProbeWithoutPongClosesTheSocket() async {
        let (socket, connector, recorder) = make(join: join)
        await socket.start()
        #expect(await eventually { await recorder.events.contains(.connected) })
        let first = connector.latest!
        await socket.wake()
        #expect(await eventually { first.sentEvents.contains("ping") })
        #expect(await eventually { first.isClosed })
        #expect(await eventually { connector.openCount == 2 })
        await socket.close()
    }

    @Test func wakeProbeAnsweredKeepsTheSocket() async {
        let (socket, connector, recorder) = make(join: join)
        await socket.start()
        #expect(await eventually { await recorder.events.contains(.connected) })
        let first = connector.latest!
        await socket.wake()
        #expect(await eventually { first.sentEvents.contains("ping") })
        first.push(Frame(event: "pong"))
        try? await Task.sleep(for: .milliseconds(80))
        #expect(!first.isClosed)
        #expect(connector.openCount == 1)
        await socket.close()
    }

    @Test func wakeWhileWaitingOnBackoffConnectsAtOnce() async {
        let (socket, connector, recorder) = make(join: join)
        await socket.start()
        #expect(await eventually { await recorder.events.contains(.connected) })
        await connector.latest!.dropFromServer()
        #expect(await eventually { await recorder.events.contains(.disconnected) })
        // Push the backoff out, then wake: the wait is skipped.
        connector.failNextOpens(3)
        #expect(await eventually(.seconds(2)) { connector.attempts >= 4 })
        let attempts = connector.attempts
        let t = ContinuousClock.now
        await socket.wake()
        #expect(await eventually { connector.attempts > attempts })
        #expect(ContinuousClock.now - t < .milliseconds(40))
        await socket.close()
    }

    @Test func closeStopsReconnecting() async {
        let (socket, connector, recorder) = make(join: join)
        await socket.start()
        #expect(await eventually { await recorder.events.contains(.connected) })
        await socket.close()
        try? await Task.sleep(for: .milliseconds(150))
        #expect(connector.openCount == 1)
        #expect(connector.latest!.isClosed)
        await socket.wake()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(connector.openCount == 1)
    }

    /// C-02: the join frame is what the socket re-sends on every reconnect, so
    /// replacing it has to change what the *next* connect announces. This is the
    /// meet-switch case — the same socket, a different meet — where a stale join
    /// would silently subscribe the reader back to the meet they just left.
    @Test func replacingTheJoinChangesWhatTheNextConnectSends() async {
        let (socket, connector, recorder) = make(join: join)
        await socket.start()
        #expect(await eventually { await recorder.events.contains(.connected) })
        #expect(connector.latest!.sentEvents == ["join_meet"])

        await socket.setJoin(Frame.joinMeet(meetID: "m2", vid: "v1"))
        await connector.latest!.dropFromServer()
        #expect(await eventually { connector.openCount == 2 })
        #expect(await eventually { connector.latest!.sentEvents == ["join_meet"] })
        let sent = try? Frame.decode(connector.latest!.sent.first ?? "")
        #expect(sent?.data.object?["meet_id"]?.string == "m2")
        await socket.close()
    }

    /// And clearing it stops the socket announcing anything at all, which is the
    /// Pi's shape: one meet, nothing to join.
    @Test func clearingTheJoinSendsNothingOnReconnect() async {
        let (socket, connector, recorder) = make(join: join)
        await socket.start()
        #expect(await eventually { await recorder.events.contains(.connected) })
        await socket.setJoin(nil)
        await connector.latest!.dropFromServer()
        #expect(await eventually { connector.openCount == 2 })
        #expect(await eventually { await recorder.count { $0 == .connected } == 2 })
        #expect(connector.latest!.sentEvents.isEmpty)
        await socket.close()
    }
}
