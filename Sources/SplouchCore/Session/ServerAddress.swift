import Foundation

/// A server's base URL, normalised so two spellings of one server share a `vid`
/// (C-10) and a hand-typed address can be checked before it is saved (P-13).
public struct ServerAddress: Sendable, Hashable, Codable {
    public let url: URL

    /// From a URL. Trailing slashes are dropped; scheme and host are lowercased.
    public init?(url: URL) {
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let scheme = comps.scheme?.lowercased(), scheme == "http" || scheme == "https",
            let host = comps.host?.lowercased(), !host.isEmpty
        else { return nil }
        comps.scheme = scheme
        comps.host = host
        comps.query = nil
        comps.fragment = nil
        // A redundant `:443` is the same server as no port at all, and P-16 made that
        // matter beyond `origin`: a scanned code is placed by comparing its address with
        // the ones already known, so two spellings have to be one value and not merely
        // one `origin`. The minting side drops it too (`shared/py/splouch_links.py`); a
        // hand-made poster is where the other spelling comes from.
        if comps.port == (scheme == "https" ? 443 : 80) { comps.port = nil }
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
        return parts.count == 4
            && parts.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) && Int($0).map { $0 <= 255 } == true }
    }

    /// P-12's cleartext floor: `http` is for the local network only — a `.local`
    /// name, which is how a Pi is reached (`_splouch._tcp` advertises one), a
    /// loopback, or a private or link-local address, which is how a Pi is typed
    /// when mDNS does not get through. This is the set the cloud's `/add` page and
    /// the Pi's code minter must hold a link to as well (`shared/py/splouch_links.py`):
    /// the three parsers either agree about which addresses exist or a printed code
    /// means one thing on one phone and another on the next.
    ///
    /// The floor is ours, not ATS's. `NSAllowsLocalNetworking` covers `.local`, but
    /// ATS does not apply to IP literals at all, so without this a typed public IP
    /// would be dialled in cleartext.
    static let localHosts: Set<String> = ["localhost"]

    public static func isLocalName(_ host: String) -> Bool {
        var h = host.lowercased()
        if h.hasPrefix("["), h.hasSuffix("]") { h = String(h.dropFirst().dropLast()) }
        if h.hasSuffix(".local") || localHosts.contains(h) { return true }
        if let v4 = ipv4Octets(h) { return isPrivateV4(v4) }
        if let v6 = ipv6Bytes(h) { return isPrivateV6(v6) }
        return false
    }

    /// Loopback `127/8`, RFC 1918 (`10/8`, `172.16/12`, `192.168/16`) and
    /// link-local `169.254/16`. `10.0.2.2`, the Android emulator's host, is in `10/8`.
    private static func isPrivateV4(_ a: [UInt8]) -> Bool {
        a[0] == 127 || a[0] == 10 || (a[0] == 172 && a[1] & 0xF0 == 16)
            || (a[0] == 192 && a[1] == 168) || (a[0] == 169 && a[1] == 254)
    }

    /// Loopback `::1`, unique-local `fc00::/7`, link-local `fe80::/10`, and an
    /// IPv4-mapped address by its IPv4 half.
    private static func isPrivateV6(_ b: [UInt8]) -> Bool {
        if b[0..<15].allSatisfy({ $0 == 0 }) && b[15] == 1 { return true }
        if b[0] & 0xFE == 0xFC { return true }
        if b[0] == 0xFE && b[1] & 0xC0 == 0x80 { return true }
        if b[0..<10].allSatisfy({ $0 == 0 }) && b[10] == 0xFF && b[11] == 0xFF { return isPrivateV4(Array(b[12...])) }
        return false
    }

    private static func ipv4Octets(_ s: String) -> [UInt8]? {
        guard looksLikeIPv4(s) else { return nil }
        return s.split(separator: ".").compactMap { UInt8($0) }
    }

    /// 16 bytes for an IPv6 literal, a `%zone` suffix (`fe80::1%en0`) ignored.
    private static func ipv6Bytes(_ s: String) -> [UInt8]? {
        guard s.contains(":") else { return nil }
        let bare = s.split(separator: "%", maxSplits: 1).first.map(String.init) ?? s
        var addr = in6_addr()
        guard inet_pton(AF_INET6, bare, &addr) == 1 else { return nil }
        return withUnsafeBytes(of: &addr) { Array($0) }
    }

    /// `http` to somewhere that is not the local network — the one address shape
    /// that parses and still must not be dialled (P-16).
    public var isCleartextToNonLocal: Bool { !isSecure && !Self.isLocalName(host) }

    public var scheme: String { url.scheme ?? "https" }
    public var host: String { url.host ?? "" }
    public var port: Int { url.port ?? (scheme == "https" ? 443 : 80) }
    public var isSecure: Bool { scheme == "https" }

    /// `scheme://host:port` — the key a `vid` is stored under. One id per server,
    /// never shared between two.
    public var origin: String { "\(scheme)://\(host):\(port)" }

    /// Host and port, no scheme: what a prompt names when it asks whether to add
    /// a server (P-16). The default port is dropped — `:443` is noise on a line
    /// whose whole job is to be recognised across a pool deck.
    public var display: String { port == (isSecure ? 443 : 80) ? host : "\(host):\(port)" }

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
