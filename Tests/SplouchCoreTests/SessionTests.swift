import Foundation
import Testing
@testable import SplouchCore

@Suite struct ServerAddressTests {
    @Test func typedBareHostIsSecure() {
        let a = ServerAddress(typed: "splouch.app")!
        #expect(a.url.absoluteString == "https://splouch.app")
        #expect(a.origin == "https://splouch.app:443")
        #expect(a.isSecure)
    }

    @Test func typedLocalHostsAreCleartext() {
        #expect(ServerAddress(typed: "splouch.local")!.url.absoluteString == "http://splouch.local")
        #expect(ServerAddress(typed: "192.168.1.20:5000")!.url.absoluteString == "http://192.168.1.20:5000")
        #expect(ServerAddress(typed: "localhost:5000")!.origin == "http://localhost:5000")
        #expect(ServerAddress(typed: "pool.example.org")!.isSecure)
    }

    @Test func explicitSchemeIsKeptAndNormalised() {
        let a = ServerAddress(typed: " HTTP://Pi.Local:5000/ ")!
        #expect(a.url.absoluteString == "http://pi.local:5000")
        #expect(a.origin == "http://pi.local:5000")
        #expect(a.port == 5000)
    }

    @Test func rejectsNonsense() {
        #expect(ServerAddress(typed: "") == nil)
        #expect(ServerAddress(typed: "ftp://x") == nil)
        #expect(ServerAddress(typed: "https://") == nil)
    }

    @Test func endpointsAndSockets() {
        let a = ServerAddress(typed: "https://x.example/base/")!
        #expect(a.endpoint("/server").absoluteString == "https://x.example/base/server")
        #expect(a.endpoint("/picker/config", query: [URLQueryItem(name: "lang", value: "fr")]).absoluteString == "https://x.example/base/picker/config?lang=fr")
        #expect(a.webSocket("/ws/scoreboard").absoluteString == "wss://x.example/base/ws/scoreboard")
        #expect(ServerAddress(typed: "http://pi.local:5000")!.webSocket("/ws/results").absoluteString == "ws://pi.local:5000/ws/results")
    }

    @Test func sameServerTwoSpellingsShareAnOrigin() {
        #expect(ServerAddress(typed: "https://Splouch.App/")!.origin == ServerAddress(typed: "splouch.app")!.origin)
        #expect(ServerAddress(typed: "https://splouch.app:443")!.origin == ServerAddress(typed: "splouch.app")!.origin)
    }

    /// P-13: the field a spectator types into accepts anything, so the separators
    /// on their own have to come back nil rather than compose into a host. These
    /// are the inputs where splitting off the host leaves nothing at all.
    @Test func separatorsOnTheirOwnAreNotAnAddress() {
        for junk in ["/", ":", "//", ":::", "://", " / "] {
            #expect(ServerAddress(typed: junk) == nil, "\(junk) should not be an address")
        }
    }

    /// The port a scheme implies when the address does not name one. It is the
    /// origin's second half, so a Pi reached as `pi.local` and as `pi.local:80`
    /// have to be one server and one `vid`, not two.
    @Test func theSchemesDefaultPortIsPartOfTheOrigin() {
        #expect(ServerAddress(typed: "http://pi.local")!.port == 80)
        #expect(ServerAddress(typed: "https://x.example")!.port == 443)
        #expect(ServerAddress(typed: "http://pi.local:5000")!.port == 5000)
        #expect(ServerAddress(typed: "http://pi.local")!.origin == ServerAddress(typed: "http://pi.local:80")!.origin)
    }

    /// C-10: one `vid` per server means two spellings of one server must not
    /// differ by anything the user cannot see. A query, a fragment and a pile of
    /// trailing slashes are all dropped on the way in.
    @Test func queriesFragmentsAndTrailingSlashesAreNormalisedAway() {
        let a = ServerAddress(typed: "https://x.example/p?q=1#f")!
        #expect(a.url.absoluteString == "https://x.example/p")
        #expect(ServerAddress(typed: "https://x.example///")!.url.absoluteString == "https://x.example")
        #expect(ServerAddress(url: URL(string: "https://x.example/p?q=1#f")!)! == a)
    }

    /// A path joins whether or not the caller spelled the leading slash, so a
    /// helper that builds one either way cannot produce `https://xserver`.
    @Test func endpointAddsTheSlashTheCallerLeftOut() {
        let base = ServerAddress(typed: "https://x.example")!
        #expect(base.endpoint("server").absoluteString == "https://x.example/server")
        #expect(base.endpoint("/server") == base.endpoint("server"))
        #expect(base.endpoint("server", query: []).absoluteString == "https://x.example/server")
    }
}

@Suite struct VidStoreTests {
    @Test func oneIdPerServerStable() {
        let store = InMemoryVidStore()
        let a = store.vid(for: "https://a.example:443")
        let b = store.vid(for: "https://b.example:443")
        #expect(a != b)
        #expect(store.vid(for: "https://a.example:443") == a)
        #expect(UUID(uuidString: a) != nil)
    }

    @Test func userDefaultsStoreIsPerOriginAndPersistent() {
        let suite = "SplouchCoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsVidStore(defaults: defaults)
        let a = store.vid(for: "https://a.example:443")
        #expect(UserDefaultsVidStore(defaults: defaults).vid(for: "https://a.example:443") == a)
        #expect(store.vid(for: "http://pi.local:5000") != a)
        #expect(UUID(uuidString: a) != nil)
    }
}

@Suite struct ContractTests {
    @Test func mismatchesAreNamed() {
        let ok = ServerInfo(kind: .cloud, name: "S", contract: .init(api: "v2", app: "v1"))
        #expect(ok.contractMismatches.isEmpty)
        let old = ServerInfo(kind: .pi, name: "P", contract: .init(api: "v1", app: "v1"))
        #expect(old.contractMismatches == ["api v1"])
    }
}

#if canImport(Network)
import Network

/// P-12. The browse plumbing is `NWBrowser` and cannot be run without a network,
/// but the two decisions inside it can: which advertised service is ours, and
/// what address a resolved endpoint becomes. Both are checked here with real
/// `Network` values and no network.
@Suite struct BonjourBrowserTests {
    func endpoint(_ host: NWEndpoint.Host, _ port: NWEndpoint.Port = 5000) -> NWEndpoint {
        .hostPort(host: host, port: port)
    }

    @Test func aResolvedHostBecomesACleartextAddressOnItsPort() {
        let v4 = BonjourBrowser.entry(name: "Piscine", remote: endpoint(.ipv4(IPv4Address("192.168.1.9")!)))
        #expect(v4?.address.url.absoluteString == "http://192.168.1.9:5000")
        #expect(v4?.name == "Piscine")
        // P-12 again: a Pi is plain HTTP. The scheme is not negotiable here.
        #expect(v4?.address.isSecure == false)

        let named = BonjourBrowser.entry(name: "Pi", remote: endpoint(.name("pi.local", nil), 8080))
        #expect(named?.address.url.absoluteString == "http://pi.local:8080")
    }

    /// An IPv6 literal has to be bracketed or the port reads as part of the
    /// address, and a link-local one carries a zone that a URI spells `%25`
    /// (RFC 6874). Foundation does that encoding; this pins it, because the
    /// bare `%` it starts from looks like a bug worth "fixing".
    @Test func ipv6LiteralsAreBracketedAndTheirZoneSurvives() {
        #expect(BonjourBrowser.entry(name: "Pi", remote: endpoint(.ipv6(IPv6Address("2001:db8::5")!)))?
            .address.url.absoluteString == "http://[2001:db8::5]:5000")
        #expect(BonjourBrowser.entry(name: "Pi", remote: endpoint(.ipv6(IPv6Address("::1")!)))?
            .address.url.absoluteString == "http://[::1]:5000")
        #expect(BonjourBrowser.entry(name: "Pi", remote: endpoint(.ipv6(IPv6Address("fe80::1%en0")!)))?
            .address.url.absoluteString == "http://[fe80::1%25en0]:5000")
    }

    /// Anything that is not a host and port is not somewhere to send a request.
    /// The browser hands over whatever the connection reported, including nil
    /// when it never became ready.
    @Test func anEndpointThatIsNotAHostAndPortIsNotAnAddress() {
        #expect(BonjourBrowser.entry(name: "Pi", remote: nil) == nil)
        #expect(BonjourBrowser.entry(name: "Pi",
                                     remote: .service(name: "Pi", type: "_splouch._tcp",
                                                      domain: "local.", interface: nil)) == nil)
    }

    /// The TXT record decides whose service it is. A relay or a display
    /// advertising the same type is not an address to offer a spectator.
    @Test func onlyAPiIsOffered() {
        #expect(BonjourBrowser.isPiService(.bonjour(NWTXTRecord(["kind": "pi"]))))
        #expect(!BonjourBrowser.isPiService(.bonjour(NWTXTRecord(["kind": "cloud"]))))
        #expect(!BonjourBrowser.isPiService(.bonjour(NWTXTRecord(["kind": "display"]))))
    }

    /// A Pi that published no `kind` predates the key. Those installs are out
    /// there, so silence is kept rather than read as "not a Pi".
    @Test func aServiceThatDoesNotSayWhatItIsIsKept() {
        #expect(BonjourBrowser.isPiService(.bonjour(NWTXTRecord([:]))))
        #expect(BonjourBrowser.isPiService(.bonjour(NWTXTRecord(["path": "/server"]))))
        #expect(BonjourBrowser.isPiService(NWBrowser.Result.Metadata.none))
    }

    /// The row's identity in the menu is the origin, not the advertised name: two
    /// Pis both called "Piscine" are two rows, and one Pi renamed mid-meet does
    /// not become a second one.
    @Test func aRowIsIdentifiedByItsOriginNotItsName() {
        let a = BonjourBrowser.entry(name: "Piscine", remote: endpoint(.ipv4(IPv4Address("192.168.1.9")!)))!
        let renamed = BonjourBrowser.entry(name: "Pool", remote: endpoint(.ipv4(IPv4Address("192.168.1.9")!)))!
        let other = BonjourBrowser.entry(name: "Piscine", remote: endpoint(.ipv4(IPv4Address("10.0.0.9")!)))!
        #expect(a.id == "http://192.168.1.9:5000")
        #expect(a.id == renamed.id)
        #expect(a.id != other.id)
    }

    /// The flag the picker shows a spinner against. Browsing starts on demand and
    /// stopping clears what was found, so a sheet reopened on another network
    /// does not start from the last one's hits.
    @MainActor
    @Test func stoppingClearsTheFlagAndTheHits() {
        let b = BonjourBrowser()
        #expect(!b.browsing)
        b.resolved(name: "Piscine", remote: endpoint(.ipv4(IPv4Address("192.168.1.9")!)))
        #expect(b.found.count == 1)

        b.start()
        #expect(b.browsing)
        b.start()                     // starting twice keeps the one browser
        #expect(b.browsing)
        b.stop()
        #expect(!b.browsing)
        #expect(b.found.isEmpty)
        b.stop()                      // and stopping an idle browser is harmless
        #expect(!b.browsing)
    }

    /// One Pi answering on two interfaces is one row. Identity is the origin, so
    /// the same host twice collapses and a second interface does not.
    @MainActor
    @Test func theSameHostResolvedTwiceIsOneRow() {
        let b = BonjourBrowser()
        b.resolved(name: "Piscine", remote: endpoint(.ipv4(IPv4Address("192.168.1.9")!)))
        b.resolved(name: "Piscine", remote: endpoint(.ipv4(IPv4Address("192.168.1.9")!)))
        #expect(b.found.count == 1)
        b.resolved(name: "Piscine", remote: endpoint(.ipv4(IPv4Address("10.0.0.9")!)))
        #expect(b.found.map(\.address.host) == ["192.168.1.9", "10.0.0.9"])
        // An endpoint it cannot use adds nothing.
        b.resolved(name: "Piscine", remote: nil)
        #expect(b.found.count == 2)
    }
}
#endif
