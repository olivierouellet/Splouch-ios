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
