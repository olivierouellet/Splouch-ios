import Foundation
import Testing

@testable import SplouchCore

/// P-06: one line, always there once the server has spoken. P-07: the privacy
/// note only while counting is on. P-20: the introduction waits for the server.
@Suite(.serialized) @MainActor struct PickerNoticeTests {
    let disclaimer = "Résultats non officiels, sujets à validation."
    let short = "Résultats non officiels"
    let note = "Les visites sont comptées"

    func serve(_ stub: StubServer, short: String? = nil, analytics: Bool = true) {
        stub.route("/server", json: #"{"kind":"cloud","name":"Splouch","contract":{"api":"v2","app":"v3"}}"#)
        let shortPair = short.map { #","results_disclaimer_short":"\#($0)""# } ?? ""
        stub.route(
            "/picker/config",
            json:
                #"{"lang":"fr","analytics_enabled":\#(analytics),"strings":{"results_disclaimer":"\#(disclaimer)"\#(shortPair),"privacy_note":"\#(note)"}}"#
        )
        stub.route("/meets", json: #"{"meets":[]}"#)
    }

    func make(_ stub: StubServer, prefs: InMemoryPreferencesStore = InMemoryPreferencesStore()) -> AppModel {
        AppModel(
            defaultServer: stub.address, preferencesStore: prefs, vidStore: InMemoryVidStore(),
            bundleCache: InMemoryBundleCache(), session: stub.session, connector: FakeConnector())
    }

    /// No picker config yet — a first launch offline — means no line, not the
    /// snapshot's copy of another server's words. Same on Android.
    @Test func noPickerConfigMeansNoLine() async {
        let stub = StubServer()
        let app = make(stub)
        await app.load()  // nothing routed: the server never answers
        #expect(app.disclaimer == nil)
        #expect(app.disclaimerShort == nil)
        #expect(app.privacyNote == nil)
    }

    @Test func theLineIsTheServersShortTextAndTapGivesTheFullOne() async {
        let stub = StubServer()
        serve(stub, short: short)
        let app = make(stub)
        await app.load()
        #expect(app.disclaimerShort == short)
        #expect(app.disclaimer == disclaimer)
    }

    /// An older server without the short key still gets a line, from `mobile`.
    @Test func aServerWithoutTheShortKeyFallsBackThroughMobile() async {
        let stub = StubServer()
        serve(stub)
        let app = make(stub)
        await app.load()
        #expect(app.disclaimer == disclaimer)
        #expect(app.disclaimerShort?.isEmpty == false)
    }

    @Test func privacyNoteOnlyWhileCounting() async {
        let stub = StubServer()
        serve(stub)
        let app = make(stub)
        await app.load()
        #expect(app.analyticsEnabled)
        #expect(app.privacyNote == note)

        serve(stub, analytics: false)
        await app.load()
        #expect(!app.analyticsEnabled)
        #expect(app.privacyNote == nil)
        #expect(app.disclaimer == disclaimer)  // P-06 is never gated
    }

    /// P-07: counting off on the server hides the section, never the choice.
    @Test func countingOffOnTheServerKeepsTheSpectatorsChoice() async {
        let stub = StubServer()
        serve(stub)
        let app = make(stub)
        await app.load()
        app.setCounting(false)

        serve(stub, analytics: false)
        await app.load()
        serve(stub, analytics: true)
        await app.load()
        #expect(!app.counting)
    }

    // MARK: - P-20

    @Test func theIntroductionWaitsForTheServer() async {
        let stub = StubServer()
        let prefs = InMemoryPreferencesStore()
        let offline = make(stub, prefs: prefs)
        await offline.load()  // first launch, no answer
        #expect(!offline.introDue)

        serve(stub)
        let online = make(stub, prefs: prefs)  // a later launch that gets one
        await online.load()
        #expect(online.introDue)
    }

    @Test func theIntroductionIsSeenOncePerInstall() async {
        let stub = StubServer()
        serve(stub)
        let prefs = InMemoryPreferencesStore()
        let app = make(stub, prefs: prefs)
        await app.load()
        app.finishIntro()  // finished or skipped
        #expect(!app.introDue)
        #expect(prefs.load().introSeen)

        let relaunched = make(stub, prefs: prefs)
        await relaunched.load()
        #expect(!relaunched.introDue)
    }

    /// Skipping is not a consent: counting stays as it was.
    @Test func skippingTheIntroductionLeavesCountingAlone() async {
        let stub = StubServer()
        serve(stub)
        let app = make(stub)
        await app.load()
        #expect(app.counting)
        app.finishIntro()
        #expect(app.counting)
    }

    // MARK: - Stored folds

    @Test func oldFoldsAreDeletedOnce() throws {
        let suite = "PickerNoticeTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(disclaimer, forKey: "splouch.fold.results.https://a.example:443")
        defaults.set(note, forKey: "splouch.fold.attendance.https://a.example:443")
        defaults.set("x", forKey: "splouch.vid.https://a.example:443")
        LegacyNoticeFolds.purge(defaults)
        #expect(defaults.string(forKey: "splouch.fold.results.https://a.example:443") == nil)
        #expect(defaults.string(forKey: "splouch.fold.attendance.https://a.example:443") == nil)
        #expect(defaults.string(forKey: "splouch.vid.https://a.example:443") == "x")

        defaults.set("y", forKey: "splouch.fold.results.https://a.example:443")
        LegacyNoticeFolds.purge(defaults)  // once: a second launch does nothing
        #expect(defaults.string(forKey: "splouch.fold.results.https://a.example:443") == "y")
    }
}
