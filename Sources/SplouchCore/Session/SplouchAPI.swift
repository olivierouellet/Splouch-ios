import Foundation

public enum APIError: Error, Sendable, Equatable {
    /// The meet is gone (`GET /meet/{id}/...` 404) — app.md A-09.
    case notFound
    case http(Int)
    case notJSON
    /// `GET /server` answered, but not as a Splouch server.
    case notASplouchServer
    /// What was typed is not an http(s) address at all.
    case invalidAddress
}

/// A `GET /i18n/{lang}` body, kept verbatim, with the validator to revalidate it
/// and its decoded form. The cache stores `body` as is: the same shape as the
/// compiled snapshot, one decoder for both (app.md T-10).
public struct CachedBundle: Sendable, Equatable {
    public var body: Data
    public var etag: String?
    public var bundle: I18nBundle

    public init(body: Data, etag: String?) throws {
        self.body = body
        self.etag = etag
        self.bundle = try I18nBundle(data: body)
    }
}

/// The REST endpoints a native client needs (api.md §4), one call each.
public struct SplouchAPI: Sendable {
    public let address: ServerAddress
    private let session: URLSession

    public init(address: ServerAddress, session: URLSession = .shared) {
        self.address = address
        self.session = session
    }

    // MARK: Both servers

    /// The handshake made before anything else (api.md §5.10, app.md P-13).
    public func server() async throws -> ServerInfo {
        let data = try await get(address.endpoint("/server"))
        do {
            return try JSONDecoder().decode(ServerInfo.self, from: data)
        } catch {
            throw APIError.notASplouchServer
        }
    }

    /// One language's strings. Pass the stored ETag to revalidate; nil back
    /// means 304, keep what you have (api.md §5.9).
    public func i18n(_ lang: String, etag: String? = nil) async throws -> CachedBundle? {
        var req = URLRequest(url: address.endpoint("/i18n/\(lang)"))
        req.cachePolicy = .reloadIgnoringLocalCacheData
        if let etag { req.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.http(0) }
        if http.statusCode == 304 { return nil }
        guard (200..<300).contains(http.statusCode) else { throw APIError.http(http.statusCode) }
        return try CachedBundle(body: data, etag: http.value(forHTTPHeaderField: "ETag"))
    }

    public func locales() async throws -> [LocaleEntry] {
        try decode([LocaleEntry].self, from: try await get(address.endpoint("/locales")))
    }

    // MARK: Cloud

    public func meets() async throws -> [MeetSummary] {
        try MeetList(data: try await get(address.endpoint("/meets"))).meets
    }

    /// `lang` names the device's choice (T-08); the server resolves it, or
    /// `Accept-Language`, and echoes the result as `lang`.
    public func pickerConfig(lang: String? = nil) async throws -> PickerConfig {
        let q = lang.map { [URLQueryItem(name: "lang", value: $0)] } ?? []
        return try PickerConfig(data: try await get(address.endpoint("/picker/config", query: q)))
    }

    public func meetConfig(_ meetID: String) async throws -> MeetConfig {
        try MeetConfig(data: try await get(address.endpoint("/meet/\(meetID)/config")))
    }

    public func schedule(meetID: String) async throws -> Schedule {
        try Schedule(data: try await get(address.endpoint("/meet/\(meetID)/schedule")))
    }

    public func servers() async throws -> ServerDirectory {
        try decode(ServerDirectory.self, from: try await get(address.endpoint("/servers")))
    }

    public func pickerImageURL(meetID: String) -> URL { address.endpoint("/picker_image/\(meetID)") }
    public func pickerLogoURL() -> URL { address.endpoint("/picker_logo") }

    // MARK: Pi

    public func piConfig() async throws -> PiDisplayConfig {
        try PiDisplayConfig(data: try await get(address.endpoint("/config")))
    }

    /// The Pi's start list — the cloud's schedule body, no meet in the path.
    public func piSchedule() async throws -> Schedule {
        try Schedule(data: try await get(address.endpoint("/schedule.json")))
    }

    // MARK: Plumbing

    private func get(_ url: URL) async throws -> Data {
        var req = URLRequest(url: url)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.http(0) }
        switch http.statusCode {
        case 200..<300: return data
        case 404: throw APIError.notFound
        default: throw APIError.http(http.statusCode)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) } catch { throw APIError.notJSON }
    }
}

public extension ServerInfo {
    /// Which contract versions differ from the ones this client was written
    /// against. Empty means a match; the app connects either way and says so.
    var contractMismatches: [String] {
        var out: [String] = []
        if contract.api != Self.expectedContract.api { out.append("api \(contract.api)") }
        if contract.app != Self.expectedContract.app { out.append("app \(contract.app)") }
        return out
    }
}
