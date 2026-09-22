import Foundation
import Observation
#if canImport(Network)
import Network
#endif

/// P-12: a Pi publishes `_splouch._tcp` (port 5000, `kind=pi`, `path=/server`)
/// over mDNS, so the app browses for it instead of asking anyone to type an
/// address. Each hit is still checked with `GET /server` before use (P-13).
@MainActor
@Observable
public final class BonjourBrowser {
    public struct Found: Sendable, Equatable, Identifiable {
        public var name: String
        public var address: ServerAddress
        public var id: String { address.origin }
    }

    public static let serviceType = "_splouch._tcp"
    public private(set) var found: [Found] = []
    public private(set) var browsing = false

    #if canImport(Network)
    private var browser: NWBrowser?
    private var resolvers: [NWConnection] = []
    #endif

    public init() {}

    public func start() {
        #if canImport(Network)
        guard browser == nil else { return }
        let b = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: .tcp)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            let endpoints = results.map { ($0.endpoint, $0.metadata) }
            Task { @MainActor in self?.resolve(endpoints) }
        }
        b.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                if case .failed = state { self?.stop() }
            }
        }
        browser = b
        browsing = true
        b.start(queue: .global(qos: .utility))
        #endif
    }

    public func stop() {
        #if canImport(Network)
        browser?.cancel()
        browser = nil
        for r in resolvers { r.cancel() }
        resolvers = []
        #endif
        browsing = false
        found = []
    }

    #if canImport(Network)
    /// P-12: the TXT record says what published the service. A record that names
    /// something other than a Pi is somebody else's `_splouch._tcp` — the cloud
    /// relay, a display — and is not an address to offer. Anything that does not
    /// say is kept: a Pi published no `kind` before the key existed, and dropping
    /// those would make the browser useless against the installs already out
    /// there. Separated from the browse plumbing because it is the part with a
    /// decision in it.
    nonisolated static func isPiService(_ metadata: NWBrowser.Result.Metadata) -> Bool {
        guard case .bonjour(let txt) = metadata, let kind = txt.dictionary["kind"] else { return true }
        return kind == "pi"
    }

    /// The address a resolved connection reports, as the app will use it. nil
    /// when the endpoint is not one it can reach. Separated for the same reason:
    /// every case below is a spelling that has to survive `ServerAddress`.
    nonisolated static func entry(name: String, remote: NWEndpoint?) -> Found? {
        guard case .hostPort(let host, let port)? = remote else { return nil }
        let hostText: String
        switch host {
        case .name(let n, _): hostText = n
        case .ipv4(let a): hostText = "\(a)"
        case .ipv6(let a): hostText = "[\(a)]"
        @unknown default: return nil
        }
        guard let address = ServerAddress(typed: "http://\(hostText):\(port.rawValue)") else { return nil }
        return Found(name: name, address: address)
    }

    private func resolve(_ endpoints: [(NWEndpoint, NWBrowser.Result.Metadata)]) {
        for r in resolvers { r.cancel() }
        resolvers = []
        found = []
        for (endpoint, metadata) in endpoints {
            guard case .service(let name, _, _, _) = endpoint else { continue }
            guard Self.isPiService(metadata) else { continue }
            let c = NWConnection(to: endpoint, using: .tcp)
            c.stateUpdateHandler = { [weak self, weak c] state in
                guard case .ready = state, let c else { return }
                let remote = c.currentPath?.remoteEndpoint
                c.cancel()
                Task { @MainActor in self?.resolved(name: name, remote: remote) }
            }
            resolvers.append(c)
            c.start(queue: .global(qos: .utility))
        }
    }

    /// One Pi on two interfaces answers twice; the menu shows it once. The origin
    /// is the identity, so the same host on wifi and ethernet is two entries and
    /// the same host reached twice is one.
    func resolved(name: String, remote: NWEndpoint?) {
        guard let hit = Self.entry(name: name, remote: remote) else { return }
        if !found.contains(hit) { found.append(hit) }
    }
    #endif
}
