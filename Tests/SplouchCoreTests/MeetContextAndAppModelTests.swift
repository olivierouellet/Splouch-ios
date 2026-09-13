import Foundation
import Testing
@testable import SplouchCore

@Suite(.serialized) @MainActor struct MeetContextTests {
    let timing = SocketTiming(heartbeat: .milliseconds(40), stale: .milliseconds(100), probe: .milliseconds(40),
                              backoffMin: .milliseconds(10), backoffMax: .milliseconds(40))

    func make(stub: StubServer, connector: FakeConnector, prefs: Preferences = Preferences(), settings: MeetSettings = MeetSettings(numLanes: 4, locale: "fr", labels: ["event": "ÉP"])) -> MeetContext {
        let api = SplouchAPI(address: stub.address, session: stub.session)
        return MeetContext(api: api, kind: .cloud, meetID: "m1", title: "Open", settings: settings,
                           stringsLoader: StringsLoader(api: api, cache: InMemoryBundleCache()), preferences: prefs,
                           vidStore: InMemoryVidStore(), connector: connector, timing: timing)
    }

    @Test func loadsScheduleOnStartAndAgainOnScheduleUpdate() async {
        let stub = StubServer()
        stub.route("/meet/m1/schedule", json: #"{"heats":[{"event":1,"heat":1,"lanes":[{"lane":1,"name":"A","club":"C"}]}]}"#)
        let connector = FakeConnector()
        let ctx = make(stub: stub, connector: connector)
        ctx.filter.add(FilterTerm(kind: .swimmer, name: "Nobody"))
        ctx.filter.add(FilterTerm(kind: .swimmer, name: "A"))
        ctx.start()
        #expect(await eventually { @MainActor in ctx.schedule?.heats.count == 1 })
        #expect(ctx.filter.terms.map(\.name) == ["A"])   // pruned to names that still exist
        _ = await eventually { connector.openCount == 3 }
        connector.connections[2].push(Frame(event: "schedule_update"))
        #expect(await eventually { stub.requestCount("/meet/m1/schedule") == 2 })
        await ctx.stop()
    }

    @Test func reloadRefetchesConfigAndRebuildsTheBoard() async {
        let stub = StubServer()
        stub.route("/meet/m1/schedule", json: #"{"heats":[]}"#)
        stub.route("/meet/m1/config", json: ##"{"name":"Open 2","live":true,"settings":{"num_lanes":6,"locale":"fr","theme_colors":{"bg":"#123456"}}}"##)
        let connector = FakeConnector()
        let ctx = make(stub: stub, connector: connector)
        ctx.start()
        _ = await eventually { connector.openCount == 3 }
        connector.connections[0].push(Frame(event: "reload", data: .object([:])))
        #expect(await eventually { @MainActor in ctx.settings.numLanes == 6 })
        #expect(ctx.title == "Open 2")
        #expect(ctx.colors.bg == "#123456")
        #expect(ctx.session.scoreboard.numLanes == 6)
        #expect(!ctx.gone)
        await ctx.stop()
    }

    @Test func meetGoneOnRefreshFlagsA09() async {
        let stub = StubServer()
        stub.route("/meet/m1/schedule", json: #"{"heats":[]}"#)
        let connector = FakeConnector()
        let ctx = make(stub: stub, connector: connector)
        ctx.start()
        await ctx.refresh()   // /meet/m1/config is not routed → 404
        #expect(ctx.gone)
        await ctx.stop()
    }

    @Test func languageFollowsTheMeetUntilTheUserChooses() async {
        let stub = StubServer()
        stub.route("/i18n/es", json: #"{"lang":"es","mobile":{"scoreboard":"Marcador X"},"labels":{"short":{"event":"PR"},"long":{"event":"PRUEBA"}}}"#)
        let connector = FakeConnector()
        let ctx = make(stub: stub, connector: connector)
        #expect(ctx.effectiveLanguage == "fr")
        #expect(ctx.strings.mobile("scoreboard") == "Tableau")
        #expect(ctx.labels == ["event": "ÉP"])   // T-04: as sent, no choice made
        ctx.setLanguage("es")
        #expect(ctx.effectiveLanguage == "es")
        #expect(await eventually { @MainActor in ctx.strings.mobile("scoreboard") == "Marcador X" })
        #expect(ctx.labels["event"] == "PR")
        ctx.setLabelStyle(.long)
        #expect(ctx.labels["event"] == "PRUEBA")
        ctx.setLanguage(nil)
        #expect(ctx.effectiveLanguage == "fr")
        #expect(ctx.labels["event"] == "ÉPREUVE")   // style still chosen → i18n table for fr
        ctx.setLabelStyle(nil)
        #expect(ctx.labels == ["event": "ÉP"])
        await ctx.stop()
    }

    @Test func eventNameFollowsTheReader() {
        let stub = StubServer()
        let ctx = make(stub: stub, connector: FakeConnector(), prefs: Preferences(language: "es"))
        let parts = EventNameParts(dist: "200", stroke: "backstroke", gender: "girls", age: "< 12")
        #expect(ctx.eventName("200 m dos", parts: parts) == "200 m espalda  —  Niñas < 12")
        #expect(ctx.eventName("Club Handicap Final", parts: nil) == "Club Handicap Final")
    }

    @Test func piContextHasNoScheduleAndNoJoin() async {
        let stub = StubServer()
        let api = SplouchAPI(address: stub.address, session: stub.session)
        let connector = FakeConnector()
        let ctx = MeetContext(api: api, kind: .pi, meetID: "ignored", title: "Pool", settings: MeetSettings(),
                              stringsLoader: StringsLoader(api: api, cache: InMemoryBundleCache()), preferences: Preferences(),
                              vidStore: InMemoryVidStore(), connector: connector, timing: timing)
        #expect(ctx.scheduleUnavailable)
        #expect(ctx.meetID == nil)
        ctx.start()
        _ = await eventually { connector.openCount == 3 }
        #expect(connector.connections.allSatisfy { $0.sent.isEmpty })
        #expect(ctx.schedule == nil)
        await ctx.stop()
    }
}

@Suite(.serialized) @MainActor struct AppModelTests {
    func cloud(_ stub: StubServer) {
        stub.route("/server", json: #"{"kind":"cloud","name":"Splouch","contract":{"api":"v2","app":"v1"}}"#)
        stub.route("/picker/config", json: #"{"title":"Splouch","lang":"fr","analytics_enabled":true,"strings":{"no_meets":"Aucune"}}"#)
        stub.route("/meets", json: #"{"meets":[{"id":"m1","name":"Open","offline":false}]}"#)
        stub.route("/servers", json: #"{"servers":[{"name":"Splouch","url":"\#(stub.address.url.absoluteString)","kind":"cloud"},{"name":"Club X","url":"https://x.example","kind":"cloud"}]}"#)
        stub.route("/locales", json: #"[{"code":"en","name":"English"},{"code":"fr","name":"Français"}]"#)
        stub.route("/meet/m1/config", json: #"{"name":"Open","app_window_title":"Open 2026","settings":{"num_lanes":6}}"#)
    }

    func make(_ stub: StubServer, prefs: Preferences = Preferences()) -> AppModel {
        AppModel(defaultServer: stub.address, preferencesStore: InMemoryPreferencesStore(prefs), vidStore: InMemoryVidStore(),
                 bundleCache: InMemoryBundleCache(), session: stub.session, connector: FakeConnector())
    }

    @Test func cloudStartLoadsThePicker() async throws {
        let stub = StubServer()
        cloud(stub)
        let app = make(stub)
        await app.start()
        #expect(app.serverInfo?.kind == .cloud)
        #expect(!app.unreachable)
        #expect(app.picker?.strings["no_meets"] == "Aucune")
        #expect(app.meets.map(\.id) == ["m1"])
        #expect(app.locales.map(\.code) == ["en", "fr"])
        #expect(app.knownServers.map(\.name) == ["Splouch", "Club X"])
        #expect(app.isDefaultServer)
        let ctx = try await app.open(app.meets[0])
        #expect(ctx.title == "Open 2026")
        #expect(ctx.settings.numLanes == 6)
    }

    @Test func unreachableServerIsReported() async {
        let stub = StubServer()
        let app = make(stub)
        await app.start()
        #expect(app.unreachable)
        #expect(app.meets.isEmpty)
    }

    @Test func probeChecksBeforeSaving() async throws {
        let stub = StubServer()
        cloud(stub)
        let app = make(stub)
        await #expect(throws: APIError.self) { try await app.probe(typed: "not a url at all ://") }
        let (address, info) = try await app.probe(typed: stub.host)
        #expect(info.name == "Splouch")
        #expect(address == stub.address)
    }

    @Test func switchingServerPersistsAndReloads() async {
        let stub = StubServer()
        cloud(stub)
        let store = InMemoryPreferencesStore()
        let app = AppModel(defaultServer: ServerAddress(typed: "https://default.example")!, preferencesStore: store,
                           vidStore: InMemoryVidStore(), bundleCache: InMemoryBundleCache(), session: stub.session,
                           connector: FakeConnector())
        await app.start()
        #expect(app.unreachable)
        let info = ServerInfo(kind: .cloud, name: "Stub", contract: .init(api: "v2", app: "v1"))
        await app.addServer(stub.address, info: info)
        #expect(!app.isDefaultServer)
        #expect(app.serverInfo?.name == "Splouch")
        #expect(store.load().server == stub.address)
        #expect(store.load().savedServers.map(\.name) == ["Stub"])
        #expect(app.meets.count == 1)
        await app.switchServer(app.defaultServer)
        #expect(store.load().server == nil)
    }

    @Test func languageChoiceIsStoredAndSentToThePicker() async {
        let stub = StubServer()
        cloud(stub)
        stub.route("/picker/config") { req in
            let lang = URLComponents(url: req.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "lang" }?.value ?? "auto"
            return .json(#"{"title":"S","lang":"\#(lang)","strings":{}}"#)
        }
        let store = InMemoryPreferencesStore()
        let app = AppModel(defaultServer: stub.address, preferencesStore: store, vidStore: InMemoryVidStore(),
                           bundleCache: InMemoryBundleCache(), session: stub.session, connector: FakeConnector())
        await app.start()
        #expect(app.picker?.lang == "auto")
        await app.setLanguage("fr")
        #expect(app.picker?.lang == "fr")
        #expect(store.load().language == "fr")
        app.setLabelStyle(.long)
        #expect(store.load().labelStyle == .long)
    }

    @Test func piStartSkipsThePicker() async throws {
        let stub = StubServer()
        stub.route("/server", json: #"{"kind":"pi","name":"Piscine","contract":{"api":"v2","app":"v1"}}"#)
        stub.route("/config", json: #"{"num_lanes":10,"meet_title":"Regional","locale":"fr"}"#)
        let app = make(stub)
        await app.start()
        #expect(app.isPi)
        #expect(app.picker == nil)
        #expect(stub.requestCount("/meets") == 0)
        let ctx = try await app.openPi()
        #expect(ctx.title == "Regional")
        #expect(ctx.settings.numLanes == 10)
        #expect(ctx.scheduleUnavailable)
    }
}
