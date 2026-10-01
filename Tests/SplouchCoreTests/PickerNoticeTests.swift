import Foundation
import Testing

@testable import SplouchCore

/// P-06, P-07: a fold is remembered per server, against the exact words folded.
@Suite(.serialized) @MainActor struct PickerNoticeTests {
    let disclaimer = "Résultats non officiels"
    let note = "Les visites sont comptées"

    func serve(_ stub: StubServer, disclaimer: String? = nil, analytics: Bool = true) {
        stub.route("/server", json: #"{"kind":"cloud","name":"Splouch","contract":{"api":"v2","app":"v2"}}"#)
        stub.route(
            "/picker/config",
            json:
                #"{"lang":"fr","analytics_enabled":\#(analytics),"strings":{"results_disclaimer":"\#(disclaimer ?? self.disclaimer)","privacy_note":"\#(note)"}}"#
        )
        stub.route("/meets", json: #"{"meets":[]}"#)
    }

    func make(_ stub: StubServer, folds: any NoticeFoldStore) -> AppModel {
        AppModel(
            defaultServer: stub.address, preferencesStore: InMemoryPreferencesStore(),
            vidStore: InMemoryVidStore(), noticeFoldStore: folds,
            bundleCache: InMemoryBundleCache(), session: stub.session, connector: FakeConnector())
    }

    /// P-06: no picker config yet — a first launch offline — means no notice,
    /// not the snapshot's copy of another server's words. Same on Android.
    @Test func noPickerConfigMeansNoNotice() async {
        let stub = StubServer()
        let app = make(stub, folds: InMemoryNoticeFoldStore())
        await app.load()  // nothing routed: the server never answers
        #expect(app.noticeText(.results) == nil)
        #expect(app.noticeText(.attendance) == nil)
    }

    @Test func aStoredTextThatMatchesStartsFolded() async {
        let stub = StubServer()
        serve(stub)
        let folds = InMemoryNoticeFoldStore()
        folds.setFolded(disclaimer, .results, origin: stub.address.origin)
        folds.setFolded(note, .attendance, origin: stub.address.origin)
        let app = make(stub, folds: folds)
        await app.load()
        #expect(app.isFolded(.results))
        #expect(app.isFolded(.attendance))
    }

    @Test func aStoredTextThatDiffersStartsExpanded() async {
        let stub = StubServer()
        serve(stub, disclaimer: "Results are unofficial")  // reworded, or another language
        let folds = InMemoryNoticeFoldStore()
        folds.setFolded(disclaimer, .results, origin: stub.address.origin)
        let app = make(stub, folds: folds)
        await app.load()
        #expect(app.noticeText(.results) == "Results are unofficial")
        #expect(!app.isFolded(.results))
        #expect(!app.isFolded(.attendance))  // nothing stored at all
    }

    @Test func foldingStoresTheTextAndUnfoldingClearsIt() async {
        let stub = StubServer()
        serve(stub)
        let folds = InMemoryNoticeFoldStore()
        let app = make(stub, folds: folds)
        await app.load()
        app.fold(.results)
        #expect(app.isFolded(.results))
        #expect(!app.isFolded(.attendance))  // each notice on its own
        #expect(folds.folded(.results, origin: stub.address.origin) == disclaimer)
        #expect(folds.folded(.attendance, origin: stub.address.origin) == nil)
        app.unfold(.results)
        #expect(!app.isFolded(.results))
        #expect(folds.folded(.results, origin: stub.address.origin) == nil)
    }

    @Test func countingOffForgetsTheAttendanceFold() async {
        let stub = StubServer()
        serve(stub)
        let folds = InMemoryNoticeFoldStore()
        let app = make(stub, folds: folds)
        await app.load()
        app.fold(.results)
        app.fold(.attendance)

        serve(stub, analytics: false)
        await app.load()
        #expect(app.noticeText(.attendance) == nil)
        #expect(folds.folded(.attendance, origin: stub.address.origin) == nil)
        #expect(app.isFolded(.results))  // P-06's fold is not P-07's

        serve(stub, analytics: true)
        await app.load()
        #expect(!app.isFolded(.attendance))  // back on, and said in full
    }

    @Test func oneServersFoldsLeaveAnotherAlone() async {
        let stub = StubServer()
        serve(stub)
        let folds = InMemoryNoticeFoldStore()
        let other = ServerAddress(typed: "https://other.example")!.origin
        folds.setFolded(disclaimer, .results, origin: other)
        folds.setFolded(note, .attendance, origin: other)
        let app = make(stub, folds: folds)
        await app.load()
        #expect(!app.isFolded(.results))
        #expect(!app.isFolded(.attendance))

        app.fold(.attendance)
        app.unfold(.results)
        #expect(folds.folded(.results, origin: other) == disclaimer)
        #expect(folds.folded(.attendance, origin: other) == note)

        // Counting off here is not counting off there.
        serve(stub, analytics: false)
        await app.load()
        #expect(folds.folded(.attendance, origin: other) == note)
    }

    @Test func theUserDefaultsStoreRoundTripsPerServer() throws {
        let defaults = try #require(UserDefaults(suiteName: "PickerNoticeTests"))
        defaults.removePersistentDomain(forName: "PickerNoticeTests")
        let store = UserDefaultsNoticeFoldStore(defaults: defaults)
        store.setFolded(disclaimer, .results, origin: "https://a.example")
        #expect(store.folded(.results, origin: "https://a.example") == disclaimer)
        #expect(store.folded(.results, origin: "https://b.example") == nil)
        #expect(store.folded(.attendance, origin: "https://a.example") == nil)
        store.setFolded(nil, .results, origin: "https://a.example")
        #expect(store.folded(.results, origin: "https://a.example") == nil)
        defaults.removePersistentDomain(forName: "PickerNoticeTests")
    }
}
