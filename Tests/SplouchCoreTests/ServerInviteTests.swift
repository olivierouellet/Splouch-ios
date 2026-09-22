import Foundation
import Testing
@testable import SplouchCore

/// P-16, the model half: a scanned code asks, and only a yes does anything.
///
/// The stub's host stands in for the app's default server, which is the only authority a
/// link may name — so the links here are built from it the way the cloud builds them.
@Suite(.serialized) @MainActor struct ServerInviteTests {
    func cloud(_ stub: StubServer, kind: String = "cloud", name: String = "Splouch") {
        stub.route("/server", json: #"{"kind":"\#(kind)","name":"\#(name)","contract":{"api":"v2","app":"v1"}}"#)
        stub.route("/picker/config", json: #"{"title":"Splouch","lang":"en"}"#)
        stub.route("/meets", json: #"{"meets":[]}"#)
        stub.route("/servers", json: #"{"servers":[]}"#)
    }

    func make(_ stub: StubServer, prefs: Preferences = Preferences()) -> AppModel {
        AppModel(defaultServer: stub.address, preferencesStore: InMemoryPreferencesStore(prefs), vidStore: InMemoryVidStore(),
                 bundleCache: InMemoryBundleCache(), session: stub.session, connector: FakeConnector())
    }

    func link(_ stub: StubServer, server: String) -> String {
        "https://\(stub.host)/add?server=\(server.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!)"
    }

    /// The whole of what a scan does: it asks. Nothing is saved, nothing is selected, and
    /// the address is not dialled — scanning a code is not consent to dial what it names.
    @Test func scanningAsksAndDoesNothingElse() async {
        let stub = StubServer()
        cloud(stub)
        let app = make(stub)
        await app.start()
        let pi = StubServer()
        cloud(pi, kind: "pi", name: "Pi")

        app.openServerLink(link(stub, server: pi.address.origin))
        #expect(app.invite?.address == pi.address)
        #expect(app.invite?.standing == .new)
        #expect(app.invite?.failure == nil)
        #expect(app.preferences.savedServers.isEmpty)
        #expect(app.server == stub.address)
        #expect(pi.requestCount("/server") == 0)   // not dialled, not even once
    }

    /// The yes runs P-13 unchanged — `GET /server`, then save, then select — and the
    /// prompt goes only when it is done.
    @Test func theYesRunsTheHandshakeThenSavesAndSelects() async {
        let stub = StubServer()
        cloud(stub)
        let app = make(stub)
        await app.start()
        let pi = StubServer()
        cloud(pi, kind: "pi", name: "Poolside Pi")

        app.openServerLink(link(stub, server: pi.address.origin))
        app.acceptInvite()
        #expect(app.invite?.checking == true)      // in the same turn the button was pressed
        #expect(await eventually { @MainActor in app.invite == nil })
        #expect(pi.requestCount("/server") >= 1)
        #expect(app.server == pi.address)
        #expect(app.preferences.savedServers.map(\.name) == ["Poolside Pi"])
        #expect(app.serverInfo?.kind == .pi)
    }

    /// A server that cannot be reached fails *in* the prompt, retryably, rather than
    /// dismissing it and leaving the picker looking untouched.
    @Test func anUnreachableServerFailsInThePrompt() async {
        let stub = StubServer()
        cloud(stub)
        let app = make(stub)
        await app.start()
        let gone = StubServer()   // routes nothing: every path 404s

        app.openServerLink(link(stub, server: gone.address.origin))
        app.acceptInvite()
        #expect(await eventually { @MainActor in app.invite?.failure != nil })
        #expect(app.invite?.failure == .notSplouch)   // a 404 is an answer, just not ours
        #expect(app.invite?.address == gone.address)  // still named, so the press can be repeated
        #expect(app.invite?.checking == false)
        #expect(app.preferences.savedServers.isEmpty)
        #expect(app.server == stub.address)

        // And the retry is the same press: the server comes back and the second yes takes.
        cloud(gone, kind: "pi", name: "Back")
        app.acceptInvite()
        #expect(await eventually { @MainActor in app.invite == nil })
        #expect(app.server == gone.address)
    }

    /// The prompt asks only what is left to ask.
    @Test func aServerAlreadyInTheListAsksToSwitchRatherThanToAdd() async {
        let stub = StubServer()
        cloud(stub)
        let other = StubServer()
        cloud(other, name: "Club X")
        let saved = Preferences(savedServers: [SavedServer(name: "Club X", address: other.address)])
        let app = make(stub, prefs: saved)
        await app.start()

        app.openServerLink(link(stub, server: other.address.origin))
        #expect(app.invite?.standing == .listed)
        app.acceptInvite()
        #expect(await eventually { @MainActor in app.invite == nil })
        #expect(app.server == other.address)
    }

    /// The server already in use and answering is told nothing but that. It asks the
    /// network **nothing**: on a deck with bad wifi, routing this through the handshake
    /// could only ever answer "cannot reach this server" over a live heat coming from
    /// that very server.
    @Test func theServerAlreadyInUseIsAskedNothingAndHasNoYesToGive() async {
        let stub = StubServer()
        cloud(stub)
        let app = make(stub)
        await app.start()
        let before = stub.requestCount("/server")

        app.openServerLink(link(stub, server: stub.address.origin))
        #expect(app.invite?.standing == .inUse)
        #expect(app.invite?.nothingToDo == true)
        app.acceptInvite()
        #expect(app.invite?.checking == false)          // the model refuses it, not the view
        #expect(stub.requestCount("/server") == before) // and nothing was asked of the network
        app.dismissInvite()
        #expect(app.invite == nil)
    }

    /// Only while it is *answering*. A selected server whose handshake failed is listed,
    /// so scanning its code re-dials it — that is a spectator whose Pi rebooted.
    @Test func aSelectedServerThatIsNotAnsweringAsksToSwitchBackToIt() async {
        let stub = StubServer()   // routes nothing yet: the handshake fails
        let app = make(stub)
        await app.start()
        #expect(app.unreachable)
        #expect(app.serverInfo == nil)

        app.openServerLink(link(stub, server: stub.address.origin))
        #expect(app.invite?.standing == .listed)

        cloud(stub, kind: "pi", name: "Rebooted")
        app.acceptInvite()
        #expect(await eventually { @MainActor in app.invite == nil })
        #expect(app.serverInfo?.name == "Rebooted")
    }

    /// A no is allowed right up to the end. On iOS the prompt's Cancel cannot be
    /// disabled out from under a finger the way the Android dialog's is, so a reader who
    /// changes their mind mid-handshake is taken at their word: the answer that arrives
    /// afterwards is dropped rather than switching the server under them.
    @Test func cancellingMidHandshakeSpendsNoYes() async {
        let stub = StubServer()
        cloud(stub)
        let app = make(stub)
        await app.start()
        let slow = StubServer()
        slow.route("/server") { _ in
            Thread.sleep(forTimeInterval: 0.2)
            return .json(#"{"kind":"pi","name":"Slow","contract":{"api":"v2","app":"v1"}}"#)
        }

        app.openServerLink(link(stub, server: slow.address.origin))
        app.acceptInvite()
        app.dismissInvite()
        #expect(app.invite == nil)
        #expect(await eventually { slow.requestCount("/server") == 1 })   // the request still ran
        try? await Task.sleep(for: .milliseconds(200))
        #expect(app.invite == nil)
        #expect(app.server == stub.address)          // and it changed nothing
        #expect(app.preferences.savedServers.isEmpty)
    }

    /// A link that does not parse still raises the prompt. A code that opens the app and
    /// then appears to do nothing cannot be told from a dead app.
    @Test func aLinkThatDoesNotParseStillRaisesThePrompt() async {
        let stub = StubServer()
        cloud(stub)
        let app = make(stub)
        await app.start()

        app.openServerLink("https://evil.example/add?server=https%3A%2F%2Fpool.example")
        #expect(app.invite?.address == nil)
        #expect(app.invite?.failure == .badLink)
        #expect(app.invite?.nothingToDo == true)
        app.acceptInvite()
        #expect(app.invite?.checking == false)   // there is nothing to accept

        app.openServerLink(link(stub, server: "http://192.168.1.10:5000"))
        #expect(app.invite?.failure == .cleartextNotLocal)
        #expect(app.invite?.address == nil)

        app.dismissInvite()
        #expect(app.invite == nil)
    }

    /// The failures the handshake itself can raise, mapped to the four words the prompt
    /// has. `notFound` is the same case as `notASplouchServer` here: something answered,
    /// and it was not a Splouch server.
    @Test func everyHandshakeFailureHasAWordOfItsOwn() {
        #expect(AppModel.failure(for: APIError.invalidAddress) == .badLink)
        #expect(AppModel.failure(for: APIError.notASplouchServer) == .notSplouch)
        #expect(AppModel.failure(for: APIError.notFound) == .notSplouch)
        #expect(AppModel.failure(for: APIError.notJSON) == .notSplouch)
        #expect(AppModel.failure(for: APIError.http(500)) == .unreachable)
        #expect(AppModel.failure(for: URLError(.notConnectedToInternet)) == .unreachable)
    }
}
