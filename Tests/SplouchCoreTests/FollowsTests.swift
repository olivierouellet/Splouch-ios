import Foundation
import Testing

@testable import SplouchCore

/// app.md §10, heat notifications: what the device keeps (N-02, N-09), when it
/// asks (N-04), what it sends and where (N-07, api.md §5.13), and the tap (N-08).
@Suite(.serialized) @MainActor struct FollowsTests {
    let timing = SocketTiming(
        heartbeat: .seconds(60), stale: .seconds(60), probe: .seconds(60),
        backoffMin: .milliseconds(10), backoffMax: .milliseconds(40))

    static let emma = FollowedSwimmer(name: "Emma Roy", club: "CNQ")
    static let token = PushToken(hex: "abcd", sandbox: true)

    func make(
        stub: StubServer, push: PushCenter?, store: InMemoryFollowStore = InMemoryFollowStore(),
        platforms: [String] = ["apns"], language: String? = "fr"
    ) -> MeetContext {
        let api = SplouchAPI(address: stub.address, session: stub.session)
        return MeetContext(
            api: api, kind: .cloud, meetID: "m1", title: "Open", settings: MeetSettings(numLanes: 4, locale: "en"),
            stringsLoader: StringsLoader(api: api, cache: InMemoryBundleCache()),
            preferences: Preferences(language: language), vidStore: InMemoryVidStore(), connector: FakeConnector(),
            timing: timing, pushPlatforms: platforms, push: push, followStore: store)
    }

    /// The body of each `PUT /meet/m1/follow`, decoded. URLSession hands a
    /// protocol the body as a stream, never as `httpBody`.
    nonisolated static func bodies(_ stub: StubServer) -> [JSONValue] {
        stub.requests.filter { $0.url?.path == "/meet/m1/follow" }.compactMap { req in
            guard let stream = req.httpBodyStream else { return nil }
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buf = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buf, maxLength: buf.count)
                if n <= 0 { break }
                data.append(buf, count: n)
            }
            return try? JSONValue.parse(data)
        }
    }

    // MARK: Wire

    @Test func theRegistrationIsTheContractsBody() throws {
        let body = FollowRegistration(
            token: Self.token, lang: "fr",
            follows: MeetFollows(swimmers: [Self.emma], lead: .heats(2), selected: false)
        ).json
        #expect(body["token"]?.string == "abcd")
        #expect(body["platform"]?.string == "apns")
        #expect(body["sandbox"]?.bool == true)
        #expect(body["lang"]?.string == "fr")
        #expect(body["swimmers"]?.array?.first?["club"]?.string == "CNQ")
        #expect(body["lead"]?["heats"]?.int == 2)
        #expect(body["lead"]?["minutes"] == nil)
        #expect(body["selected"]?.bool == false)
    }

    @Test func theConfigSaysWhichPlatformsTheNodeCanNotify() throws {
        let config = MeetConfig(json: try JSONValue.parse(Data(#"{"name":"x","push":["apns","fcm"]}"#.utf8)))
        #expect(config.push == ["apns", "fcm"])
        #expect(MeetConfig(json: try JSONValue.parse(Data(#"{"name":"x"}"#.utf8))).push.isEmpty)
    }

    @Test func aTokenIsHex() {
        #expect(PushToken(data: Data([0x0a, 0xff]), sandbox: false).hex == "0aff")
    }

    @Test func aTappedNotificationNamesItsHeat() {
        let focus = HeatFocus(userInfo: ["meet_id": "m1", "event": NSNumber(value: 12), "heat": "3"])
        #expect(focus == HeatFocus(meetID: "m1", event: "12", heat: "3"))
        #expect(HeatFocus(userInfo: ["event": 1]) == nil)
    }

    // MARK: The device

    @Test func followsAreKeptPerServerAndMeet() {
        let store = InMemoryFollowStore()
        store.set(MeetFollows(swimmers: [Self.emma]), server: "https://a", meetID: "m1")
        #expect(store.follows(server: "https://a", meetID: "m1").swimmers == [Self.emma])
        #expect(store.follows(server: "https://b", meetID: "m1").isEmpty)
        store.set(MeetFollows(), server: "https://a", meetID: "m1")
        #expect(store.load().isEmpty)  // an empty list is no row
    }

    @Test func aFilterChipBecomesOneFollowPerClub() {
        let heats = [
            ScheduleHeat(
                event: "1", heat: "1", eventName: "", time: "",
                lanes: [
                    ScheduleLane(lane: 1, name: "Emma Roy", club: "CNQ", seedTime: "", swimmers: []),
                    ScheduleLane(
                        lane: 2, name: "MEGO A", club: "MEGO", seedTime: "",
                        swimmers: [ScheduleSwimmer(name: "Emma Roy", first: "Emma")]),
                ])
        ]
        #expect(
            MeetFollows.swimmers(named: "Emma Roy", in: heats).map(\.club) == ["CNQ", "MEGO"])
    }

    // MARK: N-01, N-04, N-07

    @Test func noBellWithoutAnApnsNode() {
        let stub = StubServer()
        #expect(!make(stub: stub, push: PushCenter(), platforms: ["fcm"]).canNotify)
        #expect(!make(stub: stub, push: nil).canNotify)
        #expect(make(stub: stub, push: PushCenter()).canNotify)
    }

    @Test func theFirstFollowAsksAndThenRegisters() async {
        let stub = StubServer()
        stub.route("/meet/m1/follow") { _ in .init(status: 204) }
        let push = PushCenter(token: Self.token)
        var asked = 0
        push.ask = {
            asked += 1
            return .allowed
        }
        let store = InMemoryFollowStore()
        let ctx = make(stub: stub, push: push, store: store)
        await ctx.setFollows(MeetFollows(swimmers: [Self.emma]))
        await ctx.setFollows(MeetFollows(swimmers: [Self.emma], lead: .minutes(10)))
        #expect(asked == 1)
        let sent = Self.bodies(stub)
        #expect(sent.count == 2)
        #expect(sent.last?["lead"]?["minutes"]?.int == 10)
        #expect(sent.last?["lang"]?.string == "fr")
        #expect(store.follows(server: stub.address.origin, meetID: "m1").lead == .minutes(10))
    }

    @Test func refusedKeepsTheListButSendsNothing() async {
        let stub = StubServer()
        stub.route("/meet/m1/follow") { _ in .init(status: 204) }
        let push = PushCenter(token: Self.token)
        push.ask = { .refused }
        let ctx = make(stub: stub, push: push)
        await ctx.setFollows(MeetFollows(swimmers: [Self.emma]))
        #expect(ctx.follows.swimmers == [Self.emma])
        #expect(Self.bodies(stub).isEmpty)
        // Emptying the list still tells the server to stop.
        await ctx.setFollows(MeetFollows())
        #expect(Self.bodies(stub).first?["swimmers"]?.array?.isEmpty == true)
    }

    // MARK: N-11

    @Test func pausedSendsAnEmptyListAndKeepsTheSwimmers() async {
        let stub = StubServer()
        stub.route("/meet/m1/follow") { _ in .init(status: 204) }
        let store = InMemoryFollowStore()
        let ctx = make(stub: stub, push: PushCenter(permission: .allowed, token: Self.token), store: store)
        await ctx.setFollows(MeetFollows(swimmers: [Self.emma]))
        await ctx.setFollows(MeetFollows(swimmers: [Self.emma], enabled: false))
        await ctx.setFollows(MeetFollows(swimmers: [Self.emma]))
        let sent = Self.bodies(stub).map { $0["swimmers"]?.array?.count }
        #expect(sent == [1, 0, 1])
        #expect(store.follows(server: stub.address.origin, meetID: "m1").swimmers == [Self.emma])
    }

    @Test func pausedIsSentEvenWithoutPermission() async {
        let stub = StubServer()
        stub.route("/meet/m1/follow") { _ in .init(status: 204) }
        let ctx = make(stub: stub, push: PushCenter(permission: .refused, token: Self.token))
        await ctx.setFollows(MeetFollows(swimmers: [Self.emma], enabled: false))
        #expect(Self.bodies(stub).first?["swimmers"]?.array?.isEmpty == true)
    }

    @Test func aListSavedBeforeThePauseIsOn() throws {
        let old = #"{"swimmers":[{"name":"Emma Roy","club":"CNQ"}],"lead":{"minutes":{"_0":5}},"selected":true}"#
        let f = try JSONDecoder().decode(MeetFollows.self, from: Data(old.utf8))
        #expect(f.enabled)
        #expect(f.swimmers == [Self.emma])
        let paused = MeetFollows(swimmers: [Self.emma], enabled: false)
        let back = try JSONDecoder().decode(MeetFollows.self, from: JSONEncoder().encode(paused))
        #expect(back == paused)
    }

    @Test func aMeetHeldElsewhereIsFollowedThenAskedAgain() async {
        let stub = StubServer()
        let worker = ServerAddress(url: stub.address.url.appendingPathComponent("w2"))!
        stub.route("/meet/m1/follow") { _ in .json(#"{"base":"x"}"#, status: 409) }
        stub.route("/meet/m1/config", json: #"{"name":"Open","base":"\#(worker.url.absoluteString)"}"#)
        stub.route(
            "/w2/meet/m1/config", json: #"{"name":"Open","base":"\#(worker.url.absoluteString)","push":["apns"]}"#)
        stub.route("/w2/meet/m1/follow") { _ in .init(status: 204) }
        let ctx = make(stub: stub, push: PushCenter(permission: .allowed, token: Self.token))
        await ctx.setFollows(MeetFollows(swimmers: [Self.emma]))
        #expect(stub.requestCount("/w2/meet/m1/follow") == 1)
        #expect(ctx.follows.base == worker.url.absoluteString)
    }

    // MARK: N-09

    @Test func aGoneMeetTakesItsFollowsWithIt() async {
        let stub = StubServer()
        let store = InMemoryFollowStore()
        store.set(MeetFollows(swimmers: [Self.emma]), server: stub.address.origin, meetID: "m1")
        let ctx = make(stub: stub, push: PushCenter(), store: store)
        #expect(ctx.follows.swimmers == [Self.emma])
        await ctx.checkMeet()  // the stub answers 404
        #expect(ctx.gone)
        #expect(store.load().isEmpty)
    }

    // MARK: N-12, N-13

    func makeApp(
        _ stub: StubServer, store: InMemoryFollowStore,
        push: PushCenter = PushCenter(
            permission: .allowed, token: Self.token)
    ) -> AppModel {
        AppModel(
            defaultServer: stub.address, preferencesStore: InMemoryPreferencesStore(),
            vidStore: InMemoryVidStore(), bundleCache: InMemoryBundleCache(), session: stub.session,
            connector: FakeConnector(), followStore: store, push: push)
    }

    @Test func aFollowKeepsTheMeetsNameAndLanguage() async {
        let stub = StubServer()
        stub.route("/meet/m1/follow") { _ in .init(status: 204) }
        let store = InMemoryFollowStore()
        let ctx = make(stub: stub, push: PushCenter(permission: .allowed, token: Self.token), store: store)
        var told = 0
        ctx.onFollowsChange = { told += 1 }
        await ctx.setFollows(MeetFollows(swimmers: [Self.emma]))
        let kept = store.follows(server: stub.address.origin, meetID: "m1")
        #expect(kept.name == "Open")
        #expect(kept.lang == "en")
        #expect(told > 0)
    }

    @Test func settingsListEveryFollowedMeetByNameFromEveryServer() {
        let stub = StubServer()
        let store = InMemoryFollowStore()
        store.set(MeetFollows(swimmers: [Self.emma], name: "Zone"), server: stub.address.origin, meetID: "m1")
        store.set(MeetFollows(swimmers: [Self.emma], name: "Alpha"), server: "http://pool.local:80", meetID: "m2")
        let app = makeApp(stub, store: store)
        #expect(app.followedMeets.map { app.followedName($0) } == ["Alpha", "Zone"])
        #expect(app.followedMeets.map { app.followedServer($0) } == ["pool.local", nil])
        #expect(app.settingsSections.contains(.notifications))
        #expect(makeApp(stub, store: InMemoryFollowStore()).settingsSections.contains(.notifications) == false)
    }

    @Test func pauseAllSendsEmptyListsAndKeepsTheSwimmers() async {
        let stub = StubServer()
        stub.route("/meet/m1/follow") { _ in .init(status: 204) }
        let store = InMemoryFollowStore()
        store.set(MeetFollows(swimmers: [Self.emma]), server: stub.address.origin, meetID: "m1")
        // Paused already: nothing to send for it.
        store.set(MeetFollows(swimmers: [Self.emma], enabled: false), server: stub.address.origin, meetID: "m3")
        let app = makeApp(stub, store: store, push: PushCenter(permission: .refused, token: Self.token))
        let summary = MeetSummary(
            id: "m1", name: "Open", location: "", sport: "", organizer: "", meetDate: "", offline: false,
            hasPickerImage: false)
        #expect(app.followState(summary) == .on)
        await app.pauseAllFollows()
        #expect(Self.bodies(stub).map { $0["swimmers"]?.array?.count } == [0])
        #expect(stub.requestCount("/meet/m3/follow") == 0)
        #expect(app.followedMeets.allSatisfy { !$0.follows.enabled && $0.follows.swimmers == [Self.emma] })
        #expect(app.followState(summary) == .paused)
        #expect(
            app.followState(
                MeetSummary(
                    id: "m9", name: "Other", location: "", sport: "", organizer: "", meetDate: "", offline: false,
                    hasPickerImage: false)) == .none)
    }

    @Test func aMeetTurnedBackOnFromSettingsSendsItsList() async {
        let stub = StubServer()
        stub.route("/meet/m1/follow") { _ in .init(status: 204) }
        let store = InMemoryFollowStore()
        store.set(
            MeetFollows(swimmers: [Self.emma], enabled: false, lang: "es"), server: stub.address.origin, meetID: "m1")
        let app = makeApp(stub, store: store)
        await app.setFollowsEnabled(app.followedMeets[0], true)
        let body = Self.bodies(stub).first
        #expect(body?["swimmers"]?.array?.count == 1)
        #expect(body?["lang"]?.string == "es")
        #expect(app.followedMeets[0].follows.enabled)
    }

    @Test func aNewTokenIsSentForEveryMeetAndAGoneOneIsDropped() async {
        let stub = StubServer()
        stub.route("/meet/m1/follow") { _ in .init(status: 204) }
        let store = InMemoryFollowStore()
        store.set(MeetFollows(swimmers: [Self.emma]), server: stub.address.origin, meetID: "m1")
        store.set(MeetFollows(swimmers: [Self.emma]), server: stub.address.origin, meetID: "gone")
        let app = AppModel(
            defaultServer: stub.address, preferencesStore: InMemoryPreferencesStore(),
            vidStore: InMemoryVidStore(), bundleCache: InMemoryBundleCache(), session: stub.session,
            connector: FakeConnector(), followStore: store,
            push: PushCenter(permission: .allowed, token: Self.token))
        await app.registerAllFollows()
        #expect(stub.requestCount("/meet/m1/follow") == 1)
        #expect(store.load().keys.map { $0.hasSuffix("|m1") } == [true])
    }
}
