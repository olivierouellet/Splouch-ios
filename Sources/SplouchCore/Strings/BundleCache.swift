import Foundation

/// Where fetched `GET /i18n/{lang}` bodies live between launches (app.md T-10:
/// read the cache, draw, revalidate in the background, store what comes back).
/// Keyed by server origin as well as language: a Pi serves its own custom
/// wording, so one server's table must not stand in for another's.
public protocol BundleCache: Sendable {
    func load(origin: String, lang: String) -> CachedBundle?
    func store(_ cached: CachedBundle, origin: String, lang: String)
}

public struct FileBundleCache: BundleCache {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// `Application Support/Splouch/i18n` on this platform.
    public static func standard() -> FileBundleCache {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return FileBundleCache(directory: base.appendingPathComponent("Splouch/i18n", isDirectory: true))
    }

    /// `<origin>-<lang>.json` is the server's body verbatim; the ETag sits beside
    /// it in `<origin>-<lang>.etag`.
    private func file(origin: String, lang: String, ext: String) -> URL {
        let safe = origin.map { $0.isLetter || $0.isNumber ? String($0) : "_" }.joined()
        return directory.appendingPathComponent("\(safe)-\(lang).\(ext)")
    }

    public func load(origin: String, lang: String) -> CachedBundle? {
        guard let body = try? Data(contentsOf: file(origin: origin, lang: lang, ext: "json")) else { return nil }
        let etag = (try? String(contentsOf: file(origin: origin, lang: lang, ext: "etag"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return try? CachedBundle(body: body, etag: etag.flatMap { $0.isEmpty ? nil : $0 })
    }

    public func store(_ cached: CachedBundle, origin: String, lang: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? cached.body.write(to: file(origin: origin, lang: lang, ext: "json"), options: .atomic)
        let etagFile = file(origin: origin, lang: lang, ext: "etag")
        if let etag = cached.etag {
            try? Data(etag.utf8).write(to: etagFile, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: etagFile)
        }
    }
}

public final class InMemoryBundleCache: BundleCache, @unchecked Sendable {
    private let lock = NSLock()
    private var store: [String: CachedBundle] = [:]

    public init() {}

    public func load(origin: String, lang: String) -> CachedBundle? {
        lock.withLock { store[origin + "|" + lang] }
    }

    public func store(_ cached: CachedBundle, origin: String, lang: String) {
        lock.withLock { store[origin + "|" + lang] = cached }
    }
}

/// Builds `StringTable`s for one server: the cached or built-in table at once,
/// and a network refresh that revalidates with the ETag.
public struct StringsLoader: Sendable {
    public let api: SplouchAPI
    public let cache: any BundleCache

    public init(api: SplouchAPI, cache: any BundleCache) {
        self.api = api
        self.cache = cache
    }

    /// Immediate: what the cache holds for this server and language over the
    /// compiled snapshot. Never touches the network.
    public func table(for lang: String) -> StringTable {
        StringTable(language: lang, server: cache.load(origin: api.address.origin, lang: lang)?.bundle,
                    builtIn: BuiltInStrings.bundle(for: lang), english: BuiltInStrings.english)
    }

    /// Revalidates and stores. nil when the server said 304 or could not be
    /// reached — either way the caller keeps drawing what it has.
    public func refresh(_ lang: String) async -> StringTable? {
        let existing = cache.load(origin: api.address.origin, lang: lang)
        guard let fresh = try? await api.i18n(lang, etag: existing?.etag) else { return nil }
        cache.store(fresh, origin: api.address.origin, lang: lang)
        return StringTable(language: lang, server: fresh.bundle, builtIn: BuiltInStrings.bundle(for: lang),
                           english: BuiltInStrings.english)
    }
}
