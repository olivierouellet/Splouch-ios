import Foundation
import Testing
@testable import SplouchCore
@testable import SplouchUI

/// P-16, the words: which question the prompt asks, which buttons answer it, and what it
/// names. The alert itself is SwiftUI and needs a host; this is everything about it that
/// is a decision rather than a view.
///
/// Values are compared against `Native.*` and never against English: under `swift test`
/// every lookup returns its own key (see `NativeStringsCoverageTests`), and the
/// catalogue's three languages are that suite's business.
@Suite struct ServerInvitePromptTests {
    let pi = ServerAddress(typed: "http://splouch.local:5000")!
    let cloud = ServerAddress(typed: "https://pool.example")!

    func prompt(_ invite: ServerInvite) -> ServerInvitePrompt { ServerInvitePrompt(invite: invite) }

    /// A server offered nowhere yet: add it, or don't.
    @Test func aNewServerIsAskedToBeAdded() {
        let p = prompt(ServerInvite(address: pi, standing: .new))
        #expect(p.title == Native.addServerQuestion)
        #expect(p.confirmLabel == Native.add)
        #expect(p.showsCancel)
        #expect(!p.nothingToDo)
    }

    /// One already in the list is not added again; it is switched to.
    @Test func aListedServerIsAskedToBeSwitchedTo() {
        let p = prompt(ServerInvite(address: cloud, standing: .listed))
        #expect(p.title == Native.switchServerQuestion)
        #expect(p.confirmLabel == Native.switchTo)
        #expect(p.showsCancel)
    }

    /// The one in use has nothing to agree to: one button, and it only closes.
    @Test func theServerInUseGetsOneButtonAndNoQuestion() {
        let p = prompt(ServerInvite(address: cloud, standing: .inUse))
        #expect(p.title == Native.alreadyOnServer)
        #expect(p.nothingToDo)
        #expect(p.confirmLabel == Native.ok)
        #expect(!p.showsCancel)
        // It still names the address: "already" is only useful with an "on what".
        #expect(p.message == cloud.display)
    }

    /// The address is the whole of what is being agreed to, so it is always on screen —
    /// host and port, and no port when it is the scheme's own.
    @Test func thePromptNamesTheAddress() {
        #expect(prompt(ServerInvite(address: pi, standing: .new)).message == "splouch.local:5000")
        #expect(prompt(ServerInvite(address: cloud, standing: .new)).message == "pool.example")
    }

    /// A link with nothing in it is a refusal, not an invitation with a red line under
    /// it, so it does not borrow the list's "Add a server" header — and it says why.
    @Test func aDeadLinkIsAnApologyWithOneButton() {
        for failure in [InviteFailure.badLink, .cleartextNotLocal] {
            let p = prompt(ServerInvite(address: nil, failure: failure))
            #expect(p.title == Native.cannotAddServer)
            #expect(p.nothingToDo)
            #expect(p.confirmLabel == Native.ok)
            #expect(!p.showsCancel)
            #expect(p.message == ServerInvitePrompt.reason(failure))
        }
    }

    /// A handshake that failed keeps the question in the title and adds the reason under
    /// the address: the button is still the answer to it, which is what makes the failure
    /// retryable rather than final.
    @Test func aFailedHandshakeKeepsTheQuestionAndAddsTheReason() {
        let p = prompt(ServerInvite(address: pi, standing: .new, failure: .unreachable))
        #expect(p.title == Native.addServerQuestion)
        #expect(p.confirmLabel == Native.add)
        #expect(p.showsCancel)
        #expect(p.message == "splouch.local:5000\n\(Native.serverUnreachable)")
    }

    /// While `GET /server` is in flight the button that was pressed is the thing that
    /// reports on it, so a second press has nothing new to say.
    @Test func theButtonReportsTheHandshakeItStarted() {
        let p = prompt(ServerInvite(address: pi, standing: .new, checking: true))
        #expect(p.confirmLabel == Native.checking)
        #expect(p.showsCancel)
    }

    /// Each failure has a word of its own; none of them is a server's.
    @Test func everyFailureHasItsOwnNativeWord() {
        let all: [InviteFailure] = [.badLink, .cleartextNotLocal, .notSplouch, .unreachable]
        let words = all.map(ServerInvitePrompt.reason)
        #expect(Set(words).count == all.count)
        #expect(words.allSatisfy { !$0.isEmpty })
    }
}
