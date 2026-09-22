import SwiftUI
import SplouchCore

/// P-16: a QR code named a server, and this is the yes it needs.
///
/// It is an alert and not a sheet or a row in the server list, on purpose. The reader was
/// looking at a poster a moment ago, not at this app — often the app was not running at
/// all — so whatever is behind it is not what they came for, and the question has to be
/// the screen's only business until it is answered. **It names the address** (`display`,
/// host and port): the one thing being agreed to is which machine the app will talk to,
/// and "Add this server?" without a name is not a question.
///
/// The words are decided here rather than inside the `alert` modifier so they can be
/// tested without a host: `SplouchUITests` asserts the four titles, the two buttons and
/// the message for every standing, which is most of what this feature promises.
struct ServerInvitePrompt {
    let invite: ServerInvite

    /// The prompt asks only what is left to ask. A link with nothing in it is a refusal,
    /// not an invitation with a red line under it, so it does not borrow the list's
    /// "Add a server" header.
    var title: String {
        if invite.address == nil { return Native.cannotAddServer }
        switch invite.standing {
        case .inUse: return Native.alreadyOnServer
        case .listed: return Native.switchServerQuestion
        case .new: return Native.addServerQuestion
        }
    }

    /// The address, and under it the reason when there is one. A failed handshake keeps
    /// the question in the title — the button is still the answer to it, which is what
    /// makes the failure retryable rather than final.
    var message: String? {
        [invite.address?.display, invite.failure.map(Self.reason)]
            .compactMap { $0 }
            .joined(separator: "\n")
            .nilIfEmpty
    }

    /// Nothing to agree to: one button, and it only closes the alert.
    var nothingToDo: Bool { invite.nothingToDo }

    /// `Checking…` takes the label's place while `GET /server` is in flight, so the
    /// button that was pressed is the thing that reports on it.
    var confirmLabel: String {
        if nothingToDo { return Native.ok }
        if invite.checking { return Native.checking }
        return invite.standing == .listed ? Native.switchTo : Native.add
    }

    var showsCancel: Bool { !nothingToDo }

    /// The app's own words for each case (T-05): a link and a network are the device's
    /// business, not a meet's, so no server serves these.
    static func reason(_ failure: InviteFailure) -> String {
        switch failure {
        case .badLink: return Native.badServerLink
        case .cleartextNotLocal: return Native.cleartextNotLocal
        case .notSplouch: return Native.notSplouch
        case .unreachable: return Native.serverUnreachable
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
