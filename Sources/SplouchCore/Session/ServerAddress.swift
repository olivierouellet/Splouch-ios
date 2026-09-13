import Foundation

/// A server's base URL, normalised so two spellings of one server share a `vid`
/// (C-10) and a hand-typed address can be checked before it is saved (P-13).
public struct ServerAddress: Sendable, Hashable, Codable {
    public let url: URL

    /// From a URL. Trailing slashes are dropped; scheme and host are lowercased.
    public init?(url: URL) {
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = comps.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = comps.host?.lowercased(), !host.isEmpty else { return nil }
        comps.scheme = scheme
        comps.host = host
        comps.query = nil
        comps.fragment = nil
        while comps.path.hasSuffix("/") { comps.path.removeLast() }
        guard let normalized = comps.url else { return nil }
        self.url = normalized
    }

    /// From what a user typed. A bare host gets `https://`; a `.local` host or a
    /// raw IP gets `http://`, which is the Pi's case (cleartext on the local
    /// network only, app.md P-12).
    public init?(typed: String) {
        var text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") {
            let host = text.split(separator: "/", maxSplits: 1).first.map(String.init) ?? text
            let bare = host.split(separator: ":").first.map(String.init) ?? host
            let local = bare.hasSuffix(".local") || bare == "localhost" || Self.looksLikeIPv4(bare)
            text = (local ? "http://" : "https://") + text
        }
        guard let url = URL(string: text) else { return nil }
        self.init(url: url)
    }

    private static func looksLikeIPv4(_ s: String) -> Bool {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) && Int($0).map { $0 <= 255 } == true }
    }

    public var scheme: String { url.scheme ?? "https" }
    public var host: String { url.host ?? "" }
    public var port: Int { url.port ?? (scheme == "https" ? 443 : 80) }
    public var isSecure: Bool { scheme == "https" }

    /// `scheme://host:port` — the key a `vid` is stored under. One id per server,
    /// never shared between two.
    public var origin: String { "\(scheme)://\(host):\(port)" }

    public func endpoint(_ path: String, query: [URLQueryItem] = []) -> URL {
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        comps.path = comps.path + (path.hasPrefix("/") ? path : "/" + path)
        comps.queryItems = query.isEmpty ? nil : query
        return comps.url!
    }

    /// `ws://` for `http://`, `wss://` for `https://`.
    public func webSocket(_ path: String) -> URL {
        var comps = URLComponents(url: endpoint(path), resolvingAgainstBaseURL: false)!
        comps.scheme = isSecure ? "wss" : "ws"
        return comps.url!
    }
}
