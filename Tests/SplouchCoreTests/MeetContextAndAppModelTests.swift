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

    /// The heat the board is on, which the schedule highlights and the tabs share.
    /// It follows the scoreboard socket, and the explicit wipe clears it — a lane
    /// list that outlived its heat is the bug `reset` exists to prevent.
    @Test func theCurrentHeatFollowsTheBoardAndClearsOnReset() async {
        let stub = StubServer()
        stub.route("/meet/m1/schedule", json: #"{"heats":[]}"#)
        let connector = FakeConnector()
        let ctx = make(stub: stub, connector: connector)
        ctx.start()
        _ = await eventually { connector.openCount == 3 }
        #expect(ctx.currentHeat == nil)
        connector.connections[0].push(Frame(event: "update_scoreboard",
                                            data: .object(["current_event": .string("7"),
                                                           "current_heat": .string("3")])))
        #expect(await eventually { @MainActor in ctx.currentHeat == HeatRef(event: "7", heat: "3") })
        connector.connections[0].push(Frame(event: "reset", data: .object([:])))
        #expect(await eventually { @MainActor in ctx.currentHeat == nil })
        await ctx.stop()
    }

    /// T-09: the short/long control is withdrawn from the UI, so a meet renders
    /// the long labels whatever a device has stored — including a device that
    /// chose short while the control still existed. The stored value is read
    /// through `effectiveLabelStyle` rather than overwritten, so that choice is
    /// still there if the control ever returns.
    @Test func theMeetRendersLongLabelsWhateverTheDeviceStored() async {
        let stub = StubServer()
        stub.route("/meet/m1/schedule", json: #"{"heats":[]}"#)
        let ctx = make(stub: stub, connector: FakeConnector(), prefs: Preferences(labelStyle: .short))
        #expect(ctx.effectiveLabelStyle == .long)
        // The choice itself is kept, not overwritten: it is the reading that is
        // pinned, so the preference survives for the day the control returns.
        let stored = Preferences(labelStyle: .short)
        #expect(stored.labelStyle == .short)
        #expect(stored.effectiveLabelStyle == .long)
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

    /// Preferences written before a key existed decode to its default rather than
    /// throwing and taking the rest of the file with them. The server list is the
    /// one that matters: a decode failure there would silently drop every server
    /// the user had added, and they would have to type them again.
    @Test func preferencesMissingAKeyKeepTheRestOfTheFile() throws {
        let sparse = Data(#"{"language":"fr"}"#.utf8)
        let p = try JSONDecoder().decode(Preferences.self, from: sparse)
        #expect(p.language == "fr")
        #expect(p.savedServers.isEmpty)
        #expect(p.labelStyle == .long)
        #expect(p.appearance == .dark)
        #expect(p.server == nil)

        // An empty object is the first-launch case and decodes the same way.
        #expect(try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8)).savedServers.isEmpty)
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

    /// The header's name for a server, before and after it has said one (§7).
    /// Until `GET /server` answers there is no name to show, and the host is what
    /// the user typed — which is the state the server sheet renders a row in.
    @Test func serverNameFallsBackToTheHostUntilTheServerSaysOne() async {
        let stub = StubServer()
        cloud(stub)
        let app = make(stub)
        #expect(app.serverInfo == nil)
        #expect(app.serverName == stub.host)
        await app.start()
        #expect(app.serverName == "Splouch")
        // An unreachable server drops the name again rather than keeping a stale
        // one: switchServer clears serverInfo before the load that fails.
        await app.switchServer(ServerAddress(typed: "https://gone.example")!)
        #expect(app.unreachable)
        #expect(app.serverName == "gone.example")
    }

    /// The menu is built before any server has answered, so its first row has no
    /// name to use and falls back to the product's own.
    @Test func knownServersNamesTheCurrentServerBeforeItHasAnswered() {
        let stub = StubServer()
        let app = make(stub)
        #expect(app.knownServers.map(\.name) == ["Splouch"])
        #expect(app.knownServers.map(\.address) == [stub.address])
    }

    /// P-11: a server saved twice is one row, not two. The second add replaces
    /// the first, so a renamed server keeps the newer name at the same origin.
    @Test func addingTheSameServerTwiceKeepsOneEntryWithTheNewerName() async {
        let stub = StubServer()
        cloud(stub)
        let store = InMemoryPreferencesStore()
        let app = AppModel(defaultServer: ServerAddress(typed: "https://default.example")!, preferencesStore: store,
                           vidStore: InMemoryVidStore(), bundleCache: InMemoryBundleCache(), session: stub.session,
                           connector: FakeConnector())
        await app.addServer(stub.address, info: ServerInfo(kind: .cloud, name: "Pool", contract: .init(api: "v2", app: "v1")))
        await app.addServer(stub.address, info: ServerInfo(kind: .cloud, name: "Pool renamed", contract: .init(api: "v2", app: "v1")))
        #expect(store.load().savedServers.map(\.name) == ["Pool renamed"])
        // And the menu does not show the same origin twice either.
        #expect(app.knownServers.filter { $0.address == stub.address }.count == 1)
    }

    /// P-11: removing a saved server takes it out of the store and the menu, and
    /// leaves the others alone. Identity is the origin, not the name.
    @Test func removingASavedServerLeavesTheOthers() async {
        let stub = StubServer()
        cloud(stub)
        let app = make(stub)
        let a = SavedServer(name: "Club A", address: ServerAddress(typed: "https://a.example")!)
        let b = SavedServer(name: "Club B", address: ServerAddress(typed: "https://b.example")!)
        await app.addServer(a.address, info: ServerInfo(kind: .cloud, name: a.name, contract: .init(api: "v2", app: "v1")))
        await app.addServer(b.address, info: ServerInfo(kind: .cloud, name: b.name, contract: .init(api: "v2", app: "v1")))
        #expect(app.preferences.savedServers.map(\.name) == ["Club A", "Club B"])
        // A different SavedServer value with the same address is the same row.
        app.removeSavedServer(SavedServer(name: "whatever", address: a.address))
        #expect(app.preferences.savedServers.map(\.name) == ["Club B"])
        #expect(!app.knownServers.contains { $0.address == a.address })
        // Removing one that was never saved changes nothing.
        app.removeSavedServer(SavedServer(name: "Club C", address: ServerAddress(typed: "https://c.example")!))
        #expect(app.preferences.savedServers.map(\.name) == ["Club B"])
    }

    /// The directory is the one part of the load that is allowed to fail on its
    /// own: a cloud that cannot list its siblings still has meets to show, so
    /// `/servers` falling over empties the directory instead of the screen.
    @Test func aFailedServerDirectoryDoesNotFailTheLoad() async {
        let stub = StubServer()
        cloud(stub)
        stub.route("/servers", json: "nope", status: 500)
        let app = make(stub)
        await app.start()
        #expect(!app.unreachable)
        #expect(app.meets.count == 1)
        #expect(app.directory.isEmpty)
        // The menu still offers the current server and the default.
        #expect(app.knownServers.map(\.name) == ["Splouch"])
    }

    /// P-08: the title a meet opens under, when the server has not set the one
    /// the window prefers. `app_window_title` wins; then the meet's own name;
    /// then the name the list already showed, so the bar is never blank.
    @Test func meetTitleFallsBackThroughTheNamesItHas() async throws {
        let stub = StubServer()
        cloud(stub)
        let app = make(stub)
        await app.start()
        let summary = app.meets[0]

        stub.route("/meet/m1/config", json: #"{"name":"Open Meet","app_window_title":"","settings":{}}"#)
        #expect(try await app.open(summary).title == "Open Meet")

        stub.route("/meet/m1/config", json: #"{"name":"","app_window_title":"","settings":{}}"#)
        #expect(try await app.open(summary).title == summary.name)
    }

    /// P-14: both halves of the contract are reported, and a double mismatch
    /// reads as one notice rather than two.
    @Test func bothContractHalvesAreReported() async {
        let stub = StubServer()
        cloud(stub)
        stub.route("/server", json: #"{"kind":"cloud","name":"Old","contract":{"api":"v2","app":"v9"}}"#)
        let app = make(stub)
        await app.start()
        #expect(app.contractNotice == "app v9 ≠ v1")
        stub.route("/server", json: #"{"kind":"cloud","name":"Old","contract":{"api":"v1","app":"v9"}}"#)
        await app.load()
        #expect(app.contractNotice == "api v1 ≠ v2 · app v9 ≠ v1")
    }

    /// T-08: choosing "follow the device" clears the stored language, and the
    /// table is rebuilt from the picker's own language rather than from nothing.
    @Test func clearingTheLanguageFallsBackToThePickersOwn() async {
        let stub = StubServer()
        cloud(stub)
        let store = InMemoryPreferencesStore(Preferences(language: "es"))
        let app = AppModel(defaultServer: stub.address, preferencesStore: store, vidStore: InMemoryVidStore(),
                           bundleCache: InMemoryBundleCache(), session: stub.session, connector: FakeConnector())
        await app.start()
        #expect(store.load().language == "es")
        await app.setLanguage(nil)
        #expect(store.load().language == nil)
        // cloud() serves a picker whose own lang is fr, so that is what the
        // chrome resolves to once the device's choice is withdrawn.
        #expect(app.strings.language == "fr")
    }

    /// T-05 / T-10: the chrome starts on the compiled snapshot and upgrades to the
    /// server's own words once `GET /i18n/{lang}` answers, in the picker's language
    /// when the device has expressed no preference. What comes back is stored under
    /// this server's origin, so the next launch starts from it rather than the floor.
    @Test func chromeStringsUpgradeFromTheSnapshotToTheServersOwn() async {
        let stub = StubServer()
        cloud(stub)
        stub.route("/i18n/fr", json: #"{"lang":"fr","mobile":{"no_meets":"Rien du tout"}}"#,
                   headers: ["ETag": "\"v1\""])
        let cache = InMemoryBundleCache()
        let app = AppModel(defaultServer: stub.address, preferencesStore: InMemoryPreferencesStore(),
                           vidStore: InMemoryVidStore(), bundleCache: cache, session: stub.session,
                           connector: FakeConnector())
        await app.start()
        #expect(app.strings.language == "fr")
        #expect(app.strings.mobile("no_meets") == "Rien du tout")
        #expect(cache.load(origin: stub.address.origin, lang: "fr")?.etag == "\"v1\"")
    }

    /// The same load with the server's table unavailable: the snapshot stays, and
    /// nothing is written to the cache for it to serve stale later.
    @Test func aFailedStringRefreshLeavesTheSnapshotInPlace() async {
        let stub = StubServer()
        cloud(stub)
        stub.route("/i18n/fr", json: "kaput", status: 500)
        let cache = InMemoryBundleCache()
        let app = AppModel(defaultServer: stub.address, preferencesStore: InMemoryPreferencesStore(),
                           vidStore: InMemoryVidStore(), bundleCache: cache, session: stub.session,
                           connector: FakeConnector())
        await app.start()
        #expect(!app.unreachable)
        #expect(app.strings.language == "fr")
        #expect(cache.load(origin: stub.address.origin, lang: "fr") == nil)
    }

    /// The same, with no picker to fall back to: a Pi serves none, so the last
    /// resort is English rather than an empty language code.
    @Test func clearingTheLanguageOnAPiFallsBackToEnglish() async {
        let stub = StubServer()
        stub.route("/server", json: #"{"kind":"pi","name":"Piscine","contract":{"api":"v2","app":"v1"}}"#)
        stub.route("/config", json: #"{"num_lanes":8,"meet_title":"Local"}"#)
        let app = make(stub, prefs: Preferences(language: "fr"))
        await app.start()
        #expect(app.picker == nil)
        await app.setLanguage(nil)
        #expect(app.strings.language == "en")
    }
}
