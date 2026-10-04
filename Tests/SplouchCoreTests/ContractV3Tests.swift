import Foundation
import Testing

@testable import SplouchCore

/// app.md v3: the cloud runs several workers. C-11 (meet's own address), C-12
/// (`moved`), A-09 asked of `base`, A-12 (meet list unreachable), P-18 (compact
/// list), P-01/P-17 (province and country), P-14 against `v3`.
@Suite(.serialized) @MainActor struct ContractV3Tests {
    let timing = SocketTiming(
        heartbeat: .seconds(60), stale: .seconds(60), probe: .seconds(60),
        backoffMin: .milliseconds(10), backoffMax: .milliseconds(40))

    /// A second stub host standing in for a worker, its meets under `/w2`.
    func worker(_ stub: StubServer, path: String = "/w2") -> ServerAddress {
        ServerAddress(url: stub.address.url.appendingPathComponent(String(path.dropFirst())))!
    }

    func make(
        server: StubServer, base: ServerAddress?, connector: FakeConnector, vids: InMemoryVidStore = InMemoryVidStore()
    ) -> MeetContext {
        let api = SplouchAPI(address: server.address, session: server.session)
        return MeetContext(
            api: api, base: base, kind: .cloud, meetID: "m1", title: "Open",
            settings: MeetSettings(numLanes: 4, locale: "en"),
            stringsLoader: StringsLoader(api: api, cache: InMemoryBundleCache()), preferences: Preferences(),
            vidStore: vids, connector: connector, timing: timing)
    }

    nonisolated static func joinVid(_ c: FakeConnection) -> String? {
        c.sent.compactMap { try? Frame.decode($0) }.first { $0.event == "join_meet" }?.data.str("vid")
    }

    // MARK: Wire

    @Test func meetsCarryBaseCountryAndProvince() throws {
        let list = try MeetList(
            data: Data(
                #"""
                {"meets":[
                  {"id":"a","country":"CA","province":"QC","base":"https://ca1.splouch.org/w2","url":"https://ca1.splouch.org/w2/mobile?meet=a"},
                  {"id":"b"},
                  {"id":"c","base":"http://203.0.113.9/w1"},
                  {"id":"d","base":"http://192.168.1.20:5000"}
                ]}
                """#.utf8))
        #expect(list.meets[0].country == "CA")
        #expect(list.meets[0].province == "QC")
        #expect(list.meets[0].base?.url.absoluteString == "https://ca1.splouch.org/w2")
        #expect(list.meets[1].base == nil)  // older server → the server URL
        #expect(list.meets[1].country == "")
        #expect(list.meets[2].base == nil)  // P-12's floor: cleartext to a public host is dropped
        #expect(list.meets[3].base?.host == "192.168.1.20")
        let config = MeetConfig(
            json: try JSONValue.parse(Data(#"{"name":"x","base":"https://ca1.splouch.org/w3"}"#.utf8)))
        #expect(config.base?.url.path == "/w3")
    }

    // MARK: C-11

    @Test func socketsConfigScheduleAndIconAreAtTheMeetsBase() async {
        let server = StubServer()
        let w = StubServer()
        let base = worker(w)
        w.route("/w2/meet/m1/schedule", json: #"{"heats":[]}"#)
        w.route("/w2/meet/m1/config", json: #"{"name":"Open","settings":{"num_lanes":4}}"#)
        let connector = FakeConnector()
        let vids = InMemoryVidStore()
        let ctx = make(server: server, base: base, connector: connector, vids: vids)
        ctx.start()
        #expect(await eventually { connector.openCount == 3 })
        #expect(
            Set(connector.connections.compactMap { $0.url?.absoluteString })
                == Set(["scoreboard", "results", "schedule"].map { "wss://\(w.host)/w2/ws/\($0)" }))
        #expect(await eventually { w.requestCount("/w2/meet/m1/schedule") == 1 })
        await ctx.checkMeet()
        #expect(w.requestCount("/w2/meet/m1/config") == 1)
        #expect(server.requestCount("/meet/m1/config") == 0)
        #expect(server.requestCount("/meet/m1/schedule") == 0)
        #expect(ctx.meetAPI.iconURL(meetID: "m1").absoluteString == "https://\(w.host)/w2/icon/m1")
        // C-10 as briefed: the list's server keys the vid, not the worker.
        let vid = vids.vid(for: server.address.origin)
        #expect(await eventually { connector.connections.allSatisfy { Self.joinVid($0) == vid } })
        await ctx.stop()
    }

    @Test func withoutABaseEverythingStaysOnTheServer() async {
        let server = StubServer()
        server.route("/meet/m1/schedule", json: #"{"heats":[]}"#)
        server.route("/meet/m1/config", json: #"{"name":"Open","settings":{"num_lanes":4}}"#)
        let connector = FakeConnector()
        let ctx = make(server: server, base: nil, connector: connector)
        ctx.start()
        #expect(await eventually { connector.openCount == 3 })
        let host = server.host
        #expect(connector.connections.allSatisfy { $0.url?.host == host && $0.url?.path.hasPrefix("/ws/") == true })
        #expect(await eventually { server.requestCount("/meet/m1/schedule") == 1 })
        await ctx.checkMeet()
        #expect(server.requestCount("/meet/m1/config") == 1)
        #expect(ctx.meetAPI.iconURL(meetID: "m1").absoluteString == "https://\(server.host)/icon/m1")
        await ctx.stop()
    }

    @Test func openingAMeetAsksItsBaseAndThePickerImageStaysOnTheServer() async throws {
        let server = StubServer()
        let w = StubServer()
        AppModelTests().cloud(server)
        server.route(
            "/meets",
            json:
                #"{"meets":[{"id":"m1","name":"Open","has_picker_image":true,"base":"\#(worker(w).url.absoluteString)"}]}"#
        )
        w.route("/w2/meet/m1/config", json: #"{"name":"Worker","settings":{"num_lanes":8}}"#)
        let app = AppModelTests().make(server)
        await app.start()
        let ctx = try await app.open(app.meets[0])
        #expect(ctx.title == "Worker")
        #expect(ctx.session.base == worker(w))
        #expect(server.requestCount("/meet/m1/config") == 0)
        #expect(app.pickerImageURL(for: app.meets[0])?.host == server.host)
    }

    // MARK: C-12

    @Test func movedSwitchesBaseAndReconnectsAllThreeSockets() async {
        let server = StubServer()
        let w2 = StubServer()
        let w3 = StubServer()
        w2.route("/w2/meet/m1/schedule", json: #"{"heats":[]}"#)
        w3.route("/w3/meet/m1/config", json: #"{"name":"Moved","settings":{"num_lanes":4}}"#)
        let connector = FakeConnector()
        let ctx = make(server: server, base: worker(w2), connector: connector)
        ctx.start()
        #expect(await eventually { connector.openCount == 3 })
        let newBase = worker(w3, path: "/w3")
        connector.connection(to: "/w2/ws/results")!.push(
            Frame(
                event: "moved",
                data: .object([
                    "url": .string("\(newBase.url.absoluteString)/mobile?meet=m1"),
                    "base": .string(newBase.url.absoluteString),
                ])))
        for path in ["scoreboard", "results", "schedule"] {
            #expect(
                await eventually {
                    connector.connection(to: "/w3/ws/\(path)")?.sentEvents.contains("join_meet") == true
                })
            let old = connector.connections.filter { $0.url?.path == "/w2/ws/\(path)" }
            #expect(old.allSatisfy { $0.isClosed })
        }
        #expect(ctx.session.base == newBase)
        #expect(await eventually { w3.requestCount("/w3/meet/m1/config") >= 1 })  // config re-fetched there
        #expect(await eventually { @MainActor in ctx.title == "Moved" })
        #expect(!ctx.gone)  // never "meet gone"
        // The same move heard on another socket changes nothing more.
        connector.connection(to: "/w3/ws/scoreboard")!.push(
            Frame(event: "moved", data: .object(["base": .string(newBase.url.absoluteString)])))
        try? await Task.sleep(for: .milliseconds(100))
        #expect(connector.openCount == 6)
        await ctx.stop()
    }

    @Test func aMovedWithoutAUsableBaseIsIgnored() async {
        let server = StubServer()
        let connector = FakeConnector()
        let ctx = make(server: server, base: nil, connector: connector)
        ctx.start()
        #expect(await eventually { connector.openCount == 3 })
        connector.connection(to: "/ws/scoreboard")!.push(
            Frame(event: "moved", data: .object(["base": .string("http://203.0.113.9/w1")])))
        try? await Task.sleep(for: .milliseconds(100))
        #expect(connector.openCount == 3)
        #expect(ctx.session.base == server.address)
        await ctx.stop()
    }

    // MARK: A-09

    @Test func aConfigNamingAnotherBaseIsFollowedNotGone() async {
        let server = StubServer()
        let w2 = StubServer()
        let w3 = StubServer()
        let newBase = worker(w3, path: "/w3")
        w2.route("/w2/meet/m1/schedule", json: #"{"heats":[]}"#)
        w2.route(
            "/w2/meet/m1/config",
            json: #"{"name":"Open","base":"\#(newBase.url.absoluteString)","settings":{"num_lanes":4}}"#)
        w3.route(
            "/w3/meet/m1/config",
            json: #"{"name":"There","base":"\#(newBase.url.absoluteString)","settings":{"num_lanes":4}}"#)
        let connector = FakeConnector()
        let ctx = make(server: server, base: worker(w2), connector: connector)
        ctx.start()
        #expect(await eventually { connector.openCount == 3 })
        await ctx.checkMeet()
        #expect(ctx.session.base == newBase)
        #expect(ctx.title == "There")
        #expect(!ctx.gone)
        #expect(await eventually { connector.connection(to: "/w3/ws/scoreboard") != nil })
        // Gone is a 404 from the meet's base, not from the server.
        server.route("/meet/m1/config") { _ in .init(status: 200) }
        w3.route("/w3/meet/m1/config") { _ in .init(status: 404) }
        await ctx.checkMeet()
        #expect(ctx.gone)
        await ctx.stop()
    }

    // MARK: A-12

    @Test func theMeetListAnsweringLetsBackThrough() async {
        let server = StubServer()
        AppModelTests().cloud(server)
        let app = AppModelTests().make(server)
        await app.start()
        server.route("/meets", json: #"{"meets":[{"id":"m1"},{"id":"m2"}]}"#)
        #expect(await app.checkMeetList())
        #expect(app.meetListReachable)
        #expect(app.meets.map(\.id) == ["m1", "m2"])
    }

    @Test func aFailingMeetListKeepsTheMeet() async {
        let server = StubServer()
        AppModelTests().cloud(server)
        let app = AppModelTests().make(server)
        await app.start()
        server.route("/meets") { _ in .init(status: 502) }
        #expect(await app.checkMeetList() == false)
        #expect(!app.meetListReachable)
        #expect(app.meets.map(\.id) == ["m1"])  // the list on hand is untouched
        // It answers again: back works again.
        server.route("/meets", json: #"{"meets":[{"id":"m1"}]}"#)
        #expect(await app.checkMeetList())
        #expect(app.meetListReachable)
    }

    @Test func aSlowMeetListTimesOut() async {
        let server = StubServer()
        AppModelTests().cloud(server)
        let app = AppModelTests().make(server)
        await app.start()
        app.meetListTimeout = .milliseconds(100)
        server.route("/meets") { _ in
            Thread.sleep(forTimeInterval: 0.5)
            return .json(#"{"meets":[]}"#)
        }
        let start = ContinuousClock.now
        #expect(await app.checkMeetList() == false)
        #expect(ContinuousClock.now - start < .milliseconds(450))
        #expect(!app.meetListReachable)
        #expect(app.meets.map(\.id) == ["m1"])
    }

    // MARK: P-18

    func meets(_ n: Int) -> String {
        let rows = (1...n).map { #"{"id":"m\#($0)","has_picker_image":true}"# }
        return #"{"meets":[\#(rows.joined(separator: ","))]}"#
    }

    @Test(arguments: [(10, false), (11, true)])
    func aLongListLoadsNoImages(count: Int, compact: Bool) async {
        let server = StubServer()
        AppModelTests().cloud(server)
        server.route("/meets", json: meets(count))
        let app = AppModelTests().make(server)
        await app.start()
        #expect(app.meets.count == count)
        #expect(app.listIsCompact == compact)
        let urls = app.meets.compactMap { app.pickerImageURL(for: $0) }
        #expect(urls.count == (compact ? 0 : count))
    }

    // MARK: P-01, P-17

    func meet(country: String, province: String) -> MeetSummary {
        MeetSummary(
            id: "x", name: "Open", location: "Pool", sport: "", organizer: "", meetDate: "", offline: false,
            hasPickerImage: false, country: country, province: province)
    }

    @Test func theCountryIsNamedInTheReadersLanguage() {
        let m = meet(country: "DE", province: "BY")
        #expect(m.countryName(locale: Locale(identifier: "fr")) == "Allemagne")
        #expect(m.region(locale: Locale(identifier: "en")) == "BY, Germany")
        #expect(meet(country: "", province: "QC").region(locale: Locale(identifier: "en")) == "QC")
        #expect(meet(country: "", province: "").region() == nil)
    }

    @Test(arguments: [
        ("qc", "en", true),  // province as sent
        ("ca", "en", true),  // country code
        ("canada", "en", true),  // country name, reader's language
        ("canada", "fr", true),
        ("canada", "es", true),  // Canadá, folded
        ("canadá", "es", true),
        ("deutschland", "en", false),  // not the country's own name
    ])
    func searchMatchesProvinceAndCountry(query: String, lang: String, hit: Bool) {
        let m = meet(country: "CA", province: "QC")
        #expect(MeetSearch.filter([m], query: query, locale: Locale(identifier: lang)).count == (hit ? 1 : 0))
    }

    // MARK: P-14

    @Test func theAppIsBuiltAgainstV3() async {
        #expect(ServerInfo.expectedContract == .init(api: "v2", app: "v3"))
        let server = StubServer()
        AppModelTests().cloud(server)
        server.route("/server", json: #"{"kind":"cloud","name":"Old","contract":{"api":"v2","app":"v2"}}"#)
        let app = AppModelTests().make(server)
        await app.start()
        #expect(app.contractNotice == "app v2 ≠ v3")
        #expect(app.meets.count == 1)  // a notice, never a gate
    }
}
