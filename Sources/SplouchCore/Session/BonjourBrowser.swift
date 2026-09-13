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
    private func resolve(_ endpoints: [(NWEndpoint, NWBrowser.Result.Metadata)]) {
        for r in resolvers { r.cancel() }
        resolvers = []
        found = []
        for (endpoint, metadata) in endpoints {
            guard case .service(let name, _, _, _) = endpoint else { continue }
            if case .bonjour(let txt) = metadata, let kind = txt.dictionary["kind"], kind != "pi" { continue }
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

    private func resolved(name: String, remote: NWEndpoint?) {
        guard case .hostPort(let host, let port)? = remote else { return }
        let hostText: String
        switch host {
        case .name(let n, _): hostText = n
        case .ipv4(let a): hostText = "\(a)"
        case .ipv6(let a): hostText = "[\(a)]"
        @unknown default: return
        }
        guard let address = ServerAddress(typed: "http://\(hostText):\(port.rawValue)") else { return }
        let hit = Found(name: name, address: address)
        if !found.contains(hit) { found.append(hit) }
    }
    #endif
}
