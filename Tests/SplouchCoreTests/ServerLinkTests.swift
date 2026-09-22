import Foundation
import Testing
@testable import SplouchCore

/// P-16: what a QR code may say, and what it may not.
///
/// The link is a stranger's input — printed on a poster, scanned by a camera the app
/// never sees — so every one of these is a case somebody can actually hand the app. The
/// three parsers on the three sides of this feature (this one, the cloud's `/add` page
/// and the Pi's minter, both in `shared/py/splouch_links.py`) have to agree about which
/// of them are addresses, or a code means one thing on one phone and another on the next.
@Suite struct ServerLinkTests {
    let host = "splouch.ca"

    func address(_ result: ServerLink.Result) -> ServerAddress? {
        if case .ok(let a) = result { return a }
        return nil
    }

    @Test func theCodeTheServersMintParses() {
        let link = "https://splouch.ca/add?server=http%3A%2F%2Fsplouch.local%3A5000"
        #expect(address(ServerLink.parse(link, host: host))?.origin == "http://splouch.local:5000")
    }

    /// A hand-made poster carries an origin nobody escaped. The `:` and `/` are legal in
    /// a query value, the web half percent-encodes them anyway, and a code typed into a
    /// QR generator by an operator will not be.
    @Test func anUnescapedOriginParsesToo() {
        let link = "https://splouch.ca/add?server=http://splouch.local:5000"
        #expect(address(ServerLink.parse(link, host: host))?.origin == "http://splouch.local:5000")
    }

    /// The host is the one URL the app ships knowing (P-11), and it is checked before
    /// anything in the query is read: **a server cannot mint a code that adds a
    /// different server.**
    @Test func onlyTheAppsOwnHostIsOurLink() {
        let elsewhere = "https://evil.example/add?server=https%3A%2F%2Fpool.example"
        #expect(ServerLink.parse(elsewhere, host: host) == .invalid)
        // A host that merely ends the same way is a different host.
        #expect(ServerLink.parse("https://notsplouch.ca/add?server=https%3A%2F%2Fa.example", host: host) == .invalid)
        // Case is the DNS's business, not the poster's.
        #expect(address(ServerLink.parse("https://SPLOUCH.CA/add?server=https%3A%2F%2Fa.example", host: host)) != nil)
        // Credentials in the authority are not a shape this app mints.
        #expect(ServerLink.parse("https://user:pw@splouch.ca/add?server=https%3A%2F%2Fa.example", host: host) == .invalid)
    }

    /// `http` on the link itself is not our link either: the AASA is served over TLS and
    /// a cleartext code to the cloud is somebody else's.
    @Test func theLinkItselfMustBeHttps() {
        #expect(ServerLink.parse("http://splouch.ca/add?server=https%3A%2F%2Fa.example", host: host) == .invalid)
        #expect(ServerLink.parse("splouch://add?server=https%3A%2F%2Fa.example", host: host) == .invalid)
        #expect(ServerLink.parse("not a url at all", host: host) == .invalid)
        #expect(ServerLink.parse("", host: host) == .invalid)
    }

    /// Exactly `/add`, because that is what the AASA's `components` claims. A prefix
    /// match would swallow `/address` and every other page starting with those four
    /// characters; a trailing slash is the same page everywhere on the web.
    @Test func thePathIsExactlyAdd() {
        #expect(ServerLink.parse("https://splouch.ca/address?server=https%3A%2F%2Fa.example", host: host) == .invalid)
        #expect(ServerLink.parse("https://splouch.ca/?server=https%3A%2F%2Fa.example", host: host) == .invalid)
        #expect(ServerLink.parse("https://splouch.ca/add/more?server=https%3A%2F%2Fa.example", host: host) == .invalid)
        #expect(address(ServerLink.parse("https://splouch.ca/add/?server=https%3A%2F%2Fa.example", host: host)) != nil)
    }

    /// The parameter is `server` and nothing that only starts like it — `?servers=` is
    /// another parameter, not a typo this may read through.
    @Test func theParameterMustBeThereAndMustBeTheRightOne() {
        #expect(ServerLink.parse("https://splouch.ca/add", host: host) == .invalid)
        #expect(ServerLink.parse("https://splouch.ca/add?server=", host: host) == .invalid)
        #expect(ServerLink.parse("https://splouch.ca/add?server=%20%20", host: host) == .invalid)
        #expect(ServerLink.parse("https://splouch.ca/add?servers=https%3A%2F%2Fa.example", host: host) == .invalid)
        #expect(ServerLink.parse("https://splouch.ca/add?server_name=x", host: host) == .invalid)
    }

    /// A query is a list, and the tail is what a server reads. A code carrying two is
    /// malformed either way; reading the same one the web half reads is worth more than
    /// refusing it.
    @Test func theLastServerValueWins() {
        let link = "https://splouch.ca/add?server=https%3A%2F%2Ffirst.example&server=https%3A%2F%2Fsecond.example"
        #expect(address(ServerLink.parse(link, host: host))?.host == "second.example")
    }

    /// P-12's floor, and the reason it is here rather than only at the socket: a printed
    /// code is a stranger's input in a way a typed address is not, so it is refused
    /// before a request is made rather than by ATS after one is.
    @Test func cleartextIsForTheLocalNetworkOnly() {
        #expect(ServerLink.parse("https://splouch.ca/add?server=http%3A%2F%2F192.168.1.10%3A5000", host: host)
                == .cleartextNotLocal)
        #expect(ServerLink.parse("https://splouch.ca/add?server=http%3A%2F%2Fpool.example", host: host)
                == .cleartextNotLocal)
        // The two that are allowed: a Pi by its mDNS name, and a developer's loopback.
        #expect(address(ServerLink.parse("https://splouch.ca/add?server=http%3A%2F%2Fsplouch.local", host: host)) != nil)
        #expect(address(ServerLink.parse("https://splouch.ca/add?server=http%3A%2F%2F127.0.0.1%3A5055", host: host)) != nil)
        // And https to the same remote host is fine — the scheme is the whole objection.
        #expect(address(ServerLink.parse("https://splouch.ca/add?server=https%3A%2F%2Fpool.example", host: host)) != nil)
    }

    /// A value that is not an address at all is `invalid`, not `cleartextNotLocal`: the
    /// prompt says different things about the two, and only one of them is about a scheme.
    @Test func aParameterThatIsNotAnAddressIsJustABadLink() {
        #expect(ServerLink.parse("https://splouch.ca/add?server=%3Cscript%3E", host: host) == .invalid)
        #expect(ServerLink.parse("https://splouch.ca/add?server=ftp%3A%2F%2Fa.example", host: host) == .invalid)
        #expect(ServerLink.parse("https://splouch.ca/add?server=%2F%2F%2F", host: host) == .invalid)
    }

    /// Two spellings of one server are one server (C-10), which is what lets the standing
    /// of a scanned address be decided by comparing it with the list.
    @Test func theAddressIsNormalisedTheWayEveryOtherOneIs() {
        let trailing = "https://splouch.ca/add?server=https%3A%2F%2FPool.Example%3A443%2F"
        #expect(address(ServerLink.parse(trailing, host: host)) == ServerAddress(typed: "https://pool.example"))
    }
}
