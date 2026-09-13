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
