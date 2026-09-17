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
        // P-15: the palette is still decoded off the wire and still reaches
        // `MeetSettings`, and the app still does not draw from it — the reader's
        // choice picks between `ThemeColors.dark` and `.light` instead.
        #expect(ctx.settings.themeColors["bg"] == "#123456")
        #expect(ctx.session.scoreboard.numLanes == 6)
        #expect(!ctx.gone)
        await ctx.stop()
    }

    // A-11: the Results tab is gated on the config the client already fetches,
    // so it must follow the operator switching consoles mid-meet — in either
    // direction — without an app restart.
    @Test func consoleChangesMidMeetFlipTheResultsTab() async {
        let stub = StubServer()
        stub.route("/meet/m1/schedule", json: #"{"heats":[]}"#)
        stub.route("/meet/m1/config", json: #"{"name":"Open","settings":{"console":{"key":"manual","timed":false}}}"#)
        let connector = FakeConnector()
        let ctx = make(stub: stub, connector: connector)
        // The meet was opened before the flag was read: a console, by default.
        #expect(ctx.showsResults)
        ctx.start()
        _ = await eventually { connector.openCount == 3 }

        // C-08 `reload` — the Pi re-registers and broadcasts it when the
        // operator switches, so the tab goes while the app is open.
        connector.connections[0].push(Frame(event: "reload", data: .object([:])))
        #expect(await eventually { @MainActor in !ctx.showsResults })

        // The console turns up at last: the same fetch brings the tab back, on
        // the A-09 path this time (reconnect / foreground).
        stub.route("/meet/m1/config", json: #"{"name":"Open","settings":{"console":{"key":"cts_gen6","timed":true}}}"#)
        ctx.foregrounded()
        #expect(await eventually { @MainActor in ctx.showsResults })

        // And back off again through pull-to-refresh (A-05).
        stub.route("/meet/m1/config", json: #"{"name":"Open","settings":{"console":{"key":"manual","timed":false}}}"#)
        await ctx.refresh()
        #expect(!ctx.showsResults)
        await ctx.stop()
    }

    @Test func reconnectAndForegroundRecheckTheMeet() async {
        let stub = StubServer()
        stub.route("/meet/m1/schedule", json: #"{"heats":[]}"#)
        stub.route("/meet/m1/config", json: #"{"name":"Open","settings":{"num_lanes":4}}"#)
        let connector = FakeConnector()
        let ctx = make(stub: stub, connector: connector)
        ctx.start()
        _ = await eventually { connector.openCount == 3 }
        #expect(stub.requestCount("/meet/m1/config") == 0)
        // Foreground: C-05 probe on every socket, and the A-09 check.
        ctx.foregrounded()
        #expect(await eventually { stub.requestCount("/meet/m1/config") == 1 })
        #expect(await eventually { connector.connections.allSatisfy { $0.sentEvents.contains("ping") } })
        // The scoreboard socket drops and comes back: checked again.
        await connector.connections[0].dropFromServer()
        #expect(await eventually { stub.requestCount("/meet/m1/config") == 2 })
        #expect(!ctx.gone)
        // The meet expires: the next check sends the user back.
        stub.route("/meet/m1/config") { _ in .init(status: 404) }
        ctx.foregrounded()
        #expect(await eventually { @MainActor in ctx.gone })
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

    @Test func languageFollowsTheMeetUntilTheUserChoosesAndTheStyleStartsLong() async {
        let stub = StubServer()
        stub.route("/i18n/es", json: #"{"lang":"es","mobile":{"scoreboard":"Marcador X"},"labels":{"short":{"event":"PR"},"long":{"event":"PRUEBA"}}}"#)
        let connector = FakeConnector()
        let ctx = make(stub: stub, connector: connector)
        #expect(ctx.effectiveLanguage == "fr")
        #expect(ctx.strings.mobile("scoreboard") == "Tableau")
        // The style starts long, so the meet's own `labels` ("ÉP") is not what
        // renders — the fr long table from the snapshot is.
        #expect(ctx.labels["event"] == "ÉPREUVE")
        ctx.setLanguage("es")
        #expect(ctx.effectiveLanguage == "es")
        #expect(await eventually { @MainActor in ctx.strings.mobile("scoreboard") == "Marcador X" })
        #expect(ctx.labels["event"] == "PRUEBA")
        ctx.setLabelStyle(.short)
        #expect(ctx.labels["event"] == "PR")
        ctx.setLanguage(nil)
        #expect(ctx.effectiveLanguage == "fr")
        #expect(ctx.labels["event"] == "ÉP")   // fr again, still short
        ctx.setLabelStyle(.long)
        #expect(ctx.labels["event"] == "ÉPREUVE")
        await ctx.stop()
    }

    @Test func eventNameFollowsTheReader() {
        let stub = StubServer()
        let ctx = make(stub: stub, connector: FakeConnector(), prefs: Preferences(language: "es"))
        let parts = EventNameParts(dist: "200", stroke: "backstroke", gender: "girls", age: "< 12")
        #expect(ctx.eventName("200 m dos", parts: parts) == "200 m espalda  —  Niñas < 12")
        #expect(ctx.eventName("Club Handicap Final", parts: nil) == "Club Handicap Final")
    }

    @Test func piContextLoadsScheduleJSONAndSendsNoJoin() async {
        let stub = StubServer()
        stub.route("/schedule.json", json: #"{"heats":[{"event":3,"heat":1,"lanes":[]}]}"#)
        let api = SplouchAPI(address: stub.address, session: stub.session)
        let connector = FakeConnector()
        let ctx = MeetContext(api: api, kind: .pi, meetID: "ignored", title: "Pool", settings: MeetSettings(),
                              stringsLoader: StringsLoader(api: api, cache: InMemoryBundleCache()), preferences: Preferences(),
                              vidStore: InMemoryVidStore(), connector: connector, timing: timing)
        #expect(ctx.meetID == nil)
        ctx.start()
        _ = await eventually { connector.openCount == 3 }
        #expect(connector.connections.allSatisfy { $0.sent.isEmpty })
        #expect(await eventually { @MainActor in ctx.schedule?.heats.count == 1 })
        await ctx.refresh()   // a Pi's config cannot 404 into A-09
        #expect(!ctx.gone)
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
        #expect(!app.loading)
    }

    @Test func probeChecksBeforeSaving() async throws {
        let stub = StubServer()
        cloud(stub)
        let app = make(stub)
        await #expect(throws: APIError.invalidAddress) { try await app.probe(typed: "not a url at all ://") }
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
        // P-15: dark until the user says otherwise, then persisted.
        #expect(store.load().appearance == .dark)
        app.setAppearance(.auto)
        #expect(app.preferences.appearance == .auto)
        #expect(store.load().appearance == .auto)
    }

    /// P-15: two palettes, both the server's own, and neither of them the meet's.
    @Test func theTwoPalettesAreTheServersNotTheMeets() {
        #expect(ThemeColors.dark.bg == "#0d0d0d")
        #expect(ThemeColors.light.bg == "#f8f8f8")
        // Every key the struct models has a value in both, so neither can fall
        // through to the other's default and render a light row in a dark board.
        #expect(Set(ThemeColors.lightDefaults.keys) == Set(ThemeColors.defaults.keys))
        #expect(ThemeColors.light.rowText == "#111111")
        #expect(ThemeColors.dark.rowText == "#e0e0e0")
        // A meet that names its own colours changes neither.
        #expect(ThemeColors.dark == ThemeColors())
    }

    /// P-15: preferences written before the control existed carry no key, and
    /// those devices were seeing a pinned-dark app, so that is what they keep.
    @Test func storedPreferencesWithoutAnAppearanceStayDark() throws {
        let older = Data(#"{"labelStyle":"long","savedServers":[]}"#.utf8)
        #expect(try JSONDecoder().decode(Preferences.self, from: older).appearance == .dark)
        let light = Data(#"{"appearance":"light","savedServers":[]}"#.utf8)
        #expect(try JSONDecoder().decode(Preferences.self, from: light).appearance == .light)
        // And it survives a round trip rather than being dropped on the way out.
        let round = try JSONDecoder().decode(Preferences.self,
                                             from: try JSONEncoder().encode(Preferences(appearance: .auto)))
        #expect(round.appearance == .auto)
    }

    @Test func languageListStartsFromTheSnapshotAndSurvivesAFailedRefresh() async {
        let stub = StubServer()
        cloud(stub)
        stub.route("/locales", json: "oops", status: 500)
        let app = make(stub)
        #expect(app.locales == BuiltInStrings.locales)
        #expect(!app.locales.isEmpty)
        await app.start()
        // Nothing usable came back: the captured list stays.
        #expect(app.locales == BuiltInStrings.locales)
        stub.route("/locales", json: #"[{"code":"en","name":"English"},{"code":"de","name":"Deutsch"}]"#)
        await app.load()
        #expect(app.locales.map(\.code) == ["en", "de"])
        stub.route("/locales") { _ in .init(status: 503) }
        await app.load()
        #expect(app.locales.map(\.code) == ["en", "de"])   // the previous list, not the floor, not empty
    }

    @Test func contractMismatchIsANoticeNotAGate() async {
        let stub = StubServer()
        cloud(stub)
        stub.route("/server", json: #"{"kind":"cloud","name":"Old","contract":{"api":"v1","app":"v1"}}"#)
        let app = make(stub)
        await app.start()
        #expect(!app.unreachable)
        #expect(app.meets.count == 1)   // connected regardless
        #expect(app.contractNotice == "api v1 ≠ v2")
        stub.route("/server", json: #"{"kind":"cloud","name":"New","contract":{"api":"v2","app":"v1"}}"#)
        await app.load()
        #expect(app.contractNotice == nil)
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
    }
}
