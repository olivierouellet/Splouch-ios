import Foundation

/// P-16: the address behind a QR code, `https://<default host>/add?server=<origin>`.
///
/// **Why an `https` link on the app's own host and not a `splouch://` scheme.** The
/// reader uses the camera they already have — Camera.app, a third-party scanner — and
/// none of those open a private scheme from a code taped to a pool wall; several refuse
/// it outright. An `https` URL they all open, and it is the only shape that answers the
/// case the poster is printed for: **the app is not installed yet**. Then nothing
/// intercepts the link, Safari lands on the page, and the page offers the store (`P-10`'s
/// hand-off, which is the web's). That half lives in the `Splouch` repo — see this repo's
/// `parity.md` `P-16` for what it must serve, including the
/// `apple-app-site-association` without which iOS never routes the link here at all.
///
/// **The host is the app's own default server** (`AppModel.defaultServer`), the one URL
/// the app ships knowing (`P-11`), and the `applinks:` entitlement names the same host —
/// a Universal Link is verified per domain and the app cannot verify a pool's Pi, which
/// has no `https` and no certificate. So the Pi travels in the query and never in the
/// authority, and a link naming any other host does not parse: **a server cannot mint a
/// code that adds a different server.**
///
/// The address inside is held to exactly what a typed one is (`P-13`):
/// `ServerAddress(typed:)`, then `P-12`'s cleartext floor — `http` only for a `.local`
/// name or a developer loopback. A printed code is a stranger's input in a way a typed
/// address is not, so the floor cannot be lower here — and the link only *proposes*.
/// Nothing is saved, selected, or even dialled until the reader says yes and
/// `GET /server` answers (`AppModel.acceptInvite`).
public enum ServerLink {
    /// The path the Universal Link is claimed for. The `components` block in the AASA
    /// names this exact string, not a prefix — a prefix would also swallow `/address`
    /// and everything else starting with those four characters.
    public static let path = "/add"

    /// The query parameter carrying the server's origin, percent-encoded.
    public static let param = "server"

    public enum Result: Sendable, Equatable {
        case ok(ServerAddress)
        /// Not our link, or ours with nothing usable in it. Either way there is no
        /// server here and the prompt has to say so in its own words.
        case invalid
        /// A real address, but `http` to a host that is not on the local network.
        case cleartextNotLocal
    }

    /// `link` is what the user activity carried; `host` is the app's default server's
    /// host, the only authority a link may name.
    public static func parse(_ link: String, host: String) -> Result {
        // URLComponents, not URL: iOS 17's URL rejects some of what a hand-made poster
        // carries before this can answer for it, and the checks below are the same ones
        // either way. Nothing is trusted out of it — scheme, host and path are each
        // asserted, and the query is read by name.
        guard let comps = URLComponents(string: link.trimmingCharacters(in: .whitespacesAndNewlines)),
              comps.scheme?.lowercased() == "https",
              // `https://splouch.ca@elsewhere.example/add` resolves to `elsewhere.example`
              // and would fail the host check anyway; a link carrying credentials at all
              // is not one this app mints, so it stops here rather than later.
              comps.user == nil, comps.password == nil,
              let linkHost = comps.host?.lowercased(), linkHost == host.lowercased(),
              trimmedPath(comps.path) == path,
              let origin = lastValue(of: param, in: comps)
        else { return .invalid }
        guard let address = ServerAddress(typed: origin) else { return .invalid }
        return address.isCleartextToNonLocal ? .cleartextNotLocal : .ok(address)
    }

    /// `/add`, `/add/`, `/add//` — a trailing slash is the same page everywhere else on
    /// the web, and a code printed with one is not a different link.
    private static func trimmedPath(_ path: String) -> String {
        var p = path
        while p.count > 1 && p.hasSuffix("/") { p.removeLast() }
        return p
    }

    /// The **last** value for `name`, percent-decoded, nil when absent or blank. Last
    /// because a query is a list and the tail is what a server would read; a code
    /// carrying two is malformed either way, and picking the same one the web half picks
    /// is worth more than refusing it.
    private static func lastValue(of name: String, in comps: URLComponents) -> String? {
        comps.queryItems?.last { $0.name == name }?.value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
