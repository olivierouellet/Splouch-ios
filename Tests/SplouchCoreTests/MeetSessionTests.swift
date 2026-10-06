import Foundation
import Testing

@testable import SplouchCore

@Suite(.serialized) @MainActor struct MeetSessionTests {
    let address = ServerAddress(typed: "https://cloud.test")!
    /// Nothing here is about the watchdog or the probe (SplouchSocketTests owns
    /// those), and the fake never answers a ping. With a short `stale`, every socket
    /// is recycled about every 100 ms, so a test that holds a connection to push
    /// frames into, or counts opens or config checks, loses whenever a busy runner
    /// makes it take longer than that. Only a backoff this short is needed; nothing
    /// closes a socket unless the test does.
    let timing = SocketTiming(
        heartbeat: .seconds(60), stale: .seconds(60), probe: .seconds(60),
        backoffMin: .milliseconds(10), backoffMax: .milliseconds(40))

    func make(kind: ServerKind = .cloud, lanes: Int = 4) -> (MeetSession, FakeConnector) {
        let connector = FakeConnector()
        let s = MeetSession(
            address: address, kind: kind, meetID: "m1", settings: MeetSettings(numLanes: lanes),
            vidStore: InMemoryVidStore(), connector: connector, timing: timing)
        return (s, connector)
    }

    func connection(_ connector: FakeConnector, _ path: String) async -> FakeConnection? {
        _ = await eventually { @MainActor in connector.connection(to: "/ws/\(path)") != nil }
        return connector.connection(to: "/ws/\(path)")
    }

    @Test func opensThreeSocketsAndJoinsEachWithTheSameVid() async {
        let (s, connector) = make()
        s.start()
        #expect(await eventually { @MainActor in s.scoreboardConnected && s.resultsConnected && s.scheduleConnected })
        #expect(connector.openCount == 3)
        let joins = connector.connections.map { c in c.sent.first.flatMap { try? Frame.decode($0) } }
        #expect(joins.allSatisfy { $0?.event == "join_meet" && $0?.data["meet_id"]?.string == "m1" })
        let vids = Set(joins.compactMap { $0?.data["vid"]?.string })
        #expect(vids.count == 1)
        #expect(UUID(uuidString: vids.first ?? "") != nil)
        await s.stop()
    }

    /// C-10: off forgets the id at once, so a meet already open stops sending it —
    /// the next reconnect's join goes without one.
    @Test func turningCountingOffDropsTheVidFromTheNextJoin() async {
        let vids = InMemoryVidStore()
        let connector = FakeConnector()
        let s = MeetSession(
            address: address, kind: .cloud, meetID: "m1", settings: MeetSettings(numLanes: 4),
            vidStore: vids, connector: connector, timing: timing)
        s.start()
        #expect(await eventually { @MainActor in s.scoreboardConnected })
        let first = connector.connection(to: "/ws/scoreboard")!
        #expect(first.sent.first.flatMap { try? Frame.decode($0) }?.data["vid"] != nil)

        vids.setCounting(false, for: address.origin)
        s.refreshJoin()
        try? await Task.sleep(for: .milliseconds(50))  // the sockets take the new join
        await first.dropFromServer()
        #expect(await eventually { @MainActor in connector.connection(to: "/ws/scoreboard") !== first })
        #expect(await eventually { @MainActor in connector.connection(to: "/ws/scoreboard")!.sent.first != nil })
        let rejoin = connector.connection(to: "/ws/scoreboard")!.sent.first.flatMap { try? Frame.decode($0) }
        #expect(rejoin?.event == "join_meet")
        #expect(rejoin?.data["vid"] == nil)
        await s.stop()
    }

    /// C-10: a spectator who refused counting on this server still joins, with
    /// no `vid` — and none is created by joining.
    @Test func joinsCarryNoVidWhileCountingIsOff() async {
        let vids = InMemoryVidStore()
        vids.setCounting(false, for: address.origin)
        let connector = FakeConnector()
        let s = MeetSession(
            address: address, kind: .cloud, meetID: "m1", settings: MeetSettings(numLanes: 4),
            vidStore: vids, connector: connector, timing: timing)
        s.start()
        #expect(await eventually { @MainActor in s.scoreboardConnected && s.resultsConnected && s.scheduleConnected })
        let joins = connector.connections.map { c in c.sent.first.flatMap { try? Frame.decode($0) } }
        #expect(joins.count == 3)
        #expect(joins.allSatisfy { $0?.event == "join_meet" && $0?.data["meet_id"]?.string == "m1" })
        #expect(joins.allSatisfy { $0?.data["vid"] == nil })
        #expect(vids.vid(for: address.origin) == nil)
        await s.stop()
    }

    @Test func aPiSessionSendsNoJoin() async {
        let (s, connector) = make(kind: .pi)
        #expect(s.meetID == nil)
        s.start()
        #expect(await eventually { @MainActor in connector.openCount == 3 })
        #expect(connector.connections.allSatisfy { $0.sent.isEmpty })
        await s.stop()
    }

    @Test func scoreboardFramesDriveTheBoardAndCurrentHeat() async {
        let (s, connector) = make()
        s.start()
        let sb = await connection(connector, "scoreboard")!
        sb.push(Frame(event: "meet_live", data: .object(["live": .bool(true)])))
        sb.push(
            Frame(
                event: "update_scoreboard",
                data: .object([
                    "current_event": .string("3"), "current_heat": .string("2"),
                    "lane_name1": .string("A"), "lane_running1": .bool(true), "running_time": .string("12.00"),
                ])))
        #expect(await eventually { @MainActor in s.scoreboard[lane: 1].name == "A" })
        #expect(s.meetLive)
        #expect(s.scoreboard[lane: 1].time == "12.0")
        #expect(s.currentHeat == HeatRef(event: "3", heat: "2"))
        s.tick(at: .now + .seconds(1))
        #expect(s.scoreboard[lane: 1].time.hasPrefix("13."))
        await s.stop()
    }

    @Test func resultsSnapshotFillsAndDisconnectWipes() async {
        let (s, connector) = make()
        s.start()
        let rs = await connection(connector, "results")!
        rs.push(Frame(event: "meet_live", data: .object(["live": .bool(true)])))
        rs.push(
            Frame(
                event: "results_snapshot",
                data: .object([
                    "event": .string("5"), "heat": .string("1"), "sort": .string("lane"),
                    "lanes": .array([
                        .object([
                            "channel": .number(2), "place": .string("1"), "time": .string("30.00"),
                            "name": .string("B"),
                        ])
                    ]),
                ])))
        #expect(await eventually { @MainActor in s.results != nil })
        #expect(s.resultsLive)
        #expect(s.currentHeat == HeatRef(event: "5", heat: "1"))
        #expect(ResultsBoard.rows(s.results!, numLanes: 4)[1].name == "B")
        await rs.dropFromServer()
        #expect(await eventually { @MainActor in s.results == nil })
        #expect(!s.resultsLive)
        await s.stop()
    }

    @Test func meetLiveFalseOnResultsWipes() async {
        let (s, connector) = make()
        s.start()
        let rs = await connection(connector, "results")!
        rs.push(
            Frame(
                event: "results_snapshot",
                data: .object([
                    "event": .string("5"), "heat": .string("1"),
                    "lanes": .array([.object(["channel": .number(1), "time": .string("1.00")])]),
                ])))
        #expect(await eventually { @MainActor in s.results != nil })
        rs.push(Frame(event: "meet_live", data: .object(["live": .bool(false)])))
        #expect(await eventually { @MainActor in s.results == nil })
        await s.stop()
    }

    @Test func scheduleUpdateAndReloadBumpVersions() async {
        let (s, connector) = make()
        s.start()
        let sc = await connection(connector, "schedule")!
        let sb = await connection(connector, "scoreboard")!
        sc.push(Frame(event: "schedule_update"))
        sb.push(Frame(event: "reload", data: .object([:])))
        sb.push(Frame(event: "test_mode", data: .object(["active": .bool(true)])))  // Pi burst, ignored
        #expect(await eventually { @MainActor in s.scheduleVersion == 1 && s.reloadVersion == 1 })
        await s.stop()
    }

    // api.md §2.2: the Pi's end-of-test wipe reaches the board. `test_mode
    // {active: false}` must not — that one only takes the badge down, and an
    // operator who stopped a replay to study the last heat still has it.
    @Test func resetWipesTheBoardAndTheBadgeComingDownDoesNot() async {
        let (s, connector) = make()
        s.start()
        let sb = await connection(connector, "scoreboard")!
        sb.push(
            Frame(
                event: "update_scoreboard",
                data: .object([
                    "current_event": .string("3"), "current_heat": .string("1"),
                    "expected_splits": .number(8), "split_step": .number(2),
                    "lane_name1": .string("SARA LEBLANC"), "lane_splits1": .number(6),
                ])))
        #expect(await eventually { @MainActor in s.scoreboard[lane: 1].splits == 6 })

        sb.push(Frame(event: "test_mode", data: .object(["active": .bool(false)])))
        #expect(await eventually { @MainActor in s.scoreboard[lane: 1].splits == 6 })

        sb.push(Frame(event: "reset", data: .object([:])))
        #expect(
            await eventually { @MainActor in
                s.scoreboard[lane: 1] == LaneRow() && s.scoreboard.expectedSplits == 0
                    && s.scoreboard.currentEvent == "" && s.currentHeat == nil
            })
        await s.stop()
    }

    @Test func whicheverSocketSpeaksLastOwnsTheCurrentHeat() async {
        let (s, connector) = make()
        s.start()
        let sb = await connection(connector, "scoreboard")!
        let rs = await connection(connector, "results")!
        rs.push(
            Frame(
                event: "results_snapshot",
                data: .object([
                    "event": .string("5"), "heat": .string("1"),
                    "lanes": .array([.object(["channel": .number(1), "time": .string("1.00")])]),
                ])))
        #expect(await eventually { @MainActor in s.currentHeat == HeatRef(event: "5", heat: "1") })
        sb.push(
            Frame(
                event: "update_scoreboard",
                data: .object(["current_event": .string("5"), "current_heat": .string("2")])))
        #expect(await eventually { @MainActor in s.currentHeat == HeatRef(event: "5", heat: "2") })
        // A frame without event/heat keys leaves it alone.
        sb.push(Frame(event: "update_scoreboard", data: .object(["lane_name1": .string("x")])))
        #expect(await eventually { @MainActor in s.scoreboard[lane: 1].name == "x" })
        #expect(s.currentHeat == HeatRef(event: "5", heat: "2"))
        await s.stop()
    }

    @Test func applyingSettingsWithNewLaneCountRebuildsTheBoardAndRejoins() async {
        let (s, connector) = make(lanes: 4)
        s.start()
        let sb = await connection(connector, "scoreboard")!
        sb.push(Frame(event: "update_scoreboard", data: .object(["lane_name1": .string("A")])))
        #expect(await eventually { @MainActor in s.scoreboard[lane: 1].name == "A" })
        s.apply(settings: MeetSettings(numLanes: 6))
        #expect(s.scoreboard.numLanes == 6)
        #expect(s.scoreboard[lane: 1].name == "")
        #expect(await eventually { @MainActor in sb.sentEvents.filter { $0 == "join_meet" }.count == 2 })
        await s.stop()
    }

    @Test func resultsTabShownRejoinsOrWakes() async {
        let (s, connector) = make()
        s.start()
        let rs = await connection(connector, "results")!
        s.resultsTabShown()
        #expect(await eventually { @MainActor in rs.sentEvents.filter { $0 == "join_meet" }.count == 2 })
        await s.stop()
    }

    @Test func wakeProbesEverySocket() async {
        let (s, connector) = make()
        s.start()
        _ = await connection(connector, "schedule")
        s.wake()
        #expect(await eventually { @MainActor in connector.connections.allSatisfy { $0.sentEvents.contains("ping") } })
        await s.stop()
    }

    /// L-12: backgrounding stops the race clock and leaves it stopped. A tick
    /// that arrives afterwards — a timer that had already fired, a tab coming
    /// back before the next frame — must not restart it, or the board would
    /// resume counting from a time the console never sent.
    @Test func suspendStopsTheClockAndATickDoesNotRestartIt() async {
        let (s, connector) = make()
        s.start()
        let board = await connection(connector, "scoreboard")
        board?.push(Frame(event: "meet_live", data: .object(["live": .bool(true)])))
        board?.push(
            Frame(
                event: "update_scoreboard",
                data: .object(["lane_running1": .bool(true), "running_time": .string("10.00")])))
        #expect(await eventually { @MainActor in s.scoreboard.clock.isRunning })

        s.suspend()
        #expect(!s.scoreboard.clock.isRunning)
        s.tick(at: .now)
        #expect(!s.scoreboard.clock.isRunning)
        await s.stop()
    }

    @Test func stopClosesAndWipes() async {
        let (s, connector) = make()
        s.start()
        _ = await connection(connector, "schedule")
        await s.stop()
        #expect(connector.connections.allSatisfy { $0.isClosed })
        #expect(!s.scoreboard.connected)
        #expect(s.results == nil)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(connector.openCount == 3)
    }
}
