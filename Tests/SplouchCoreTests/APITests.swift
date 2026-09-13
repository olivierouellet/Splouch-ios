import Foundation
import Testing
@testable import SplouchCore

@Suite(.serialized) struct SplouchAPITests {
    @Test func serverHandshake() async throws {
        let stub = StubServer()
        stub.route("/server", json: #"{"kind":"cloud","name":"Club X","contract":{"api":"v2","app":"v1"}}"#)
        let api = SplouchAPI(address: stub.address, session: stub.session)
        let info = try await api.server()
        #expect(info.kind == .cloud)
        #expect(info.name == "Club X")
    }

    @Test func nonSplouchAnswerIsNamed() async {
        let stub = StubServer()
        stub.route("/server", json: #"{"hello":"world"}"#)
        let api = SplouchAPI(address: stub.address, session: stub.session)
        await #expect(throws: APIError.notASplouchServer) { try await api.server() }
        stub.route("/server", json: "oops", status: 500)
        await #expect(throws: APIError.http(500)) { try await api.server() }
    }

    @Test func meetConfig404IsNotFound() async {
        let stub = StubServer()
        let api = SplouchAPI(address: stub.address, session: stub.session)
        await #expect(throws: APIError.notFound) { try await api.meetConfig("gone") }
    }

    @Test func i18nRevalidatesWithETag() async throws {
        let stub = StubServer()
        stub.route("/i18n/fr") { req in
            if req.value(forHTTPHeaderField: "If-None-Match") == "\"abc\"" { return .init(status: 304) }
            return .json(#"{"lang":"fr","mobile":{"scoreboard":"Tableau"}}"#, headers: ["ETag": "\"abc\""])
        }
        let api = SplouchAPI(address: stub.address, session: stub.session)
        let first = try await api.i18n("fr")
        #expect(first?.bundle.mobile["scoreboard"] == "Tableau")
        #expect(first?.etag == "\"abc\"")
        let second = try await api.i18n("fr", etag: "\"abc\"")
        #expect(second == nil)
    }

    @Test func pickerConfigPassesTheChosenLanguage() async throws {
        let stub = StubServer()
        stub.route("/picker/config") { req in
            let lang = URLComponents(url: req.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "lang" }?.value ?? "none"
            return .json(#"{"title":"S","lang":"\#(lang)","strings":{}}"#)
        }
        let api = SplouchAPI(address: stub.address, session: stub.session)
        #expect(try await api.pickerConfig(lang: "es").lang == "es")
        #expect(try await api.pickerConfig().lang == "none")
    }

    @Test func searchSuggestionsCarryMeetAndQuery() async throws {
        let stub = StubServer()
        stub.route("/search_suggestions") { req in
            let q = URLComponents(url: req.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let dict = Dictionary(uniqueKeysWithValues: q.map { ($0.name, $0.value ?? "") })
            return .json(#"[{"type":"swimmer","name":"\#(dict["q"]!)","club":"\#(dict["meet_id"]!)"}]"#)
        }
        let api = SplouchAPI(address: stub.address, session: stub.session)
        let s = try await api.searchSuggestions(meetID: "m1", query: "do")
        #expect(s[0].name == "do")
        #expect(s[0].club == "m1")
    }
}

@Suite struct StringsLoaderTests {
    @Test func tableIsImmediateAndRefreshStores() async throws {
        let stub = StubServer()
        stub.route("/i18n/fr", json: #"{"lang":"fr","mobile":{"scoreboard":"Tableau serveur"}}"#, headers: ["ETag": "\"1\""])
        let cache = InMemoryBundleCache()
        let loader = StringsLoader(api: SplouchAPI(address: stub.address, session: stub.session), cache: cache)
        #expect(loader.table(for: "fr").mobile("scoreboard") == "Tableau")   // built-in until fetched
        let fresh = await loader.refresh("fr")
        #expect(fresh?.mobile("scoreboard") == "Tableau serveur")
        #expect(loader.table(for: "fr").mobile("scoreboard") == "Tableau serveur")
        #expect(cache.load(origin: stub.address.origin, lang: "fr")?.etag == "\"1\"")
    }

    @Test func refreshFailureKeepsTheCache() async {
        let stub = StubServer()
        let cache = InMemoryBundleCache()
        cache.store(CachedBundle(bundle: I18nBundle(lang: "fr", mobile: ["scoreboard": "Cached"]), etag: nil),
                    origin: stub.address.origin, lang: "fr")
        let loader = StringsLoader(api: SplouchAPI(address: stub.address, session: stub.session), cache: cache)
        #expect(await loader.refresh("fr") == nil)
        #expect(loader.table(for: "fr").mobile("scoreboard") == "Cached")
    }

    @Test func fileCacheRoundTripsPerOrigin() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("splouch-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = FileBundleCache(directory: dir)
        let c = CachedBundle(bundle: I18nBundle(lang: "fr", mobile: ["a": "b"], labels: ["short": ["event": "ÉP"]]), etag: "\"x\"")
        cache.store(c, origin: "https://a.example:443", lang: "fr")
        #expect(cache.load(origin: "https://a.example:443", lang: "fr") == c)
        #expect(cache.load(origin: "http://pi.local:5000", lang: "fr") == nil)
    }
}

@Suite struct PreferencesTests {
    @Test func roundTripThroughDefaults() {
        let suite = "SplouchCoreTests.prefs.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsPreferencesStore(defaults: defaults)
        #expect(store.load() == Preferences())
        let p = Preferences(language: "fr", labelStyle: .long, server: ServerAddress(typed: "pi.local:5000"),
                            savedServers: [SavedServer(name: "Pool", address: ServerAddress(typed: "pi.local:5000")!)])
        store.save(p)
        #expect(UserDefaultsPreferencesStore(defaults: defaults).load() == p)
    }
}
