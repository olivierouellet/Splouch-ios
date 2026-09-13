import Foundation
import Observation
import os

/// The picker and the choice of server (app.md §1, §7). One per app.
///
/// The app ships knowing one URL, the default cloud; everything else arrives as
/// data (`GET /servers`, mDNS) or is typed and checked with `GET /server`.
@MainActor
@Observable
public final class AppModel {
    public let defaultServer: ServerAddress
    private let preferencesStore: any PreferencesStore
    private let vidStore: any VidStore
    private let bundleCache: any BundleCache
    private let session: URLSession
    private let connector: any WebSocketConnector

    public private(set) var preferences: Preferences
    public private(set) var server: ServerAddress
    public private(set) var serverInfo: ServerInfo?
    public private(set) var picker: PickerConfig?
    public private(set) var meets: [MeetSummary] = []
    public private(set) var directory: [ServerEntry] = []
    public private(set) var locales: [LocaleEntry] = []
    public private(set) var loading = false
    /// The last failure reaching the server, nil when the list loaded.
    public private(set) var unreachable = false
    /// Chrome strings in the device's language.
    public private(set) var strings: StringTable
    /// P-14: the contract versions that differ from the ones this app was built
    /// against, as `api v1 ≠ v2`; nil when they match. A notice, never a gate.
    public private(set) var contractNotice: String?

    public init(defaultServer: ServerAddress, preferencesStore: any PreferencesStore = UserDefaultsPreferencesStore(),
                vidStore: any VidStore = UserDefaultsVidStore(), bundleCache: any BundleCache = FileBundleCache.standard(),
                session: URLSession = .shared, connector: any WebSocketConnector = URLSessionWebSocketConnector()) {
        self.defaultServer = defaultServer
        self.preferencesStore = preferencesStore
        self.vidStore = vidStore
        self.bundleCache = bundleCache
        self.session = session
        self.connector = connector
        let prefs = preferencesStore.load()
        self.preferences = prefs
        self.server = prefs.server ?? defaultServer
        self.strings = BuiltInStrings.table(for: prefs.language ?? Locale.current.language.languageCode?.identifier ?? "en")
    }

    public var api: SplouchAPI { SplouchAPI(address: server, session: session) }
    public var isDefaultServer: Bool { server == defaultServer }
    public var isPi: Bool { serverInfo?.kind == .pi }
    /// The name to show in the header when the server is not the default.
    public var serverName: String { serverInfo?.name ?? server.host }
    public var stringsLoader: StringsLoader { StringsLoader(api: api, cache: bundleCache) }

    /// The handshake, then the picker (cloud) or nothing more (Pi).
    public func start() async {
        await load()
    }

    /// P-09 / picker load: `GET /server`, then `/picker/config`, `/meets`,
    /// `/servers`, `/locales`.
    private static let log = Logger(subsystem: "app.splouch", category: "AppModel")

    public func load() async {
        loading = true
        defer { loading = false; Self.log.info("load finished unreachable=\(self.unreachable) meets=\(self.meets.count)") }
        let api = self.api
        Self.log.info("load start \(api.address.url.absoluteString)")
        do {
            let info = try await api.server()
            serverInfo = info
            unreachable = false
            contractNotice = Self.notice(for: info)
            if info.kind == .cloud {
                async let picker = api.pickerConfig(lang: preferences.language)
                async let meets = api.meets()
                self.picker = try await picker
                self.meets = try await meets
                directory = (try? await api.servers().servers) ?? []
            } else {
                picker = nil
                meets = []
                directory = []
            }
            locales = (try? await api.locales()) ?? []
            await refreshStrings()
        } catch {
            Self.log.error("load failed: \(String(describing: error))")
            unreachable = true
        }
    }

    // MARK: - Servers (P-11, P-13)

    /// P-13: a typed address must answer `GET /server` before it is saved.
    public func probe(typed: String) async throws -> (ServerAddress, ServerInfo) {
        guard let address = ServerAddress(typed: typed) else { throw APIError.notASplouchServer }
        let info = try await SplouchAPI(address: address, session: session).server()
        return (address, info)
    }

    /// Saves a checked address and switches to it.
    public func addServer(_ address: ServerAddress, info: ServerInfo) async {
        var p = preferences
        p.savedServers.removeAll { $0.address == address }
        p.savedServers.append(SavedServer(name: info.name, address: address))
        preferences = p
        preferencesStore.save(p)
        await switchServer(address)
    }

    public func removeSavedServer(_ saved: SavedServer) {
        var p = preferences
        p.savedServers.removeAll { $0.id == saved.id }
        preferences = p
        preferencesStore.save(p)
    }

    public func switchServer(_ address: ServerAddress) async {
        server = address
        serverInfo = nil
        contractNotice = nil
        meets = []
        picker = nil
        var p = preferences
        p.server = address == defaultServer ? nil : address
        preferences = p
        preferencesStore.save(p)
        await load()
    }

    /// Every server the menu offers: the default, the directory, hand-added.
    /// Deduplicated by origin; the current one first.
    public var knownServers: [SavedServer] {
        var out: [SavedServer] = [SavedServer(name: serverInfo?.name ?? "Splouch", address: server)]
        var seen: Set<String> = [server.origin]
        func add(_ s: SavedServer) {
            if seen.insert(s.address.origin).inserted { out.append(s) }
        }
        add(SavedServer(name: "Splouch", address: defaultServer))
        for e in directory {
            if let a = ServerAddress(typed: e.url) { add(SavedServer(name: e.name, address: a)) }
        }
        for s in preferences.savedServers { add(s) }
        return out
    }

    // MARK: - Language and labels (T-08, T-09)

    public func setLanguage(_ lang: String?) async {
        var p = preferences
        p.language = lang
        preferences = p
        preferencesStore.save(p)
        strings = stringsLoader.table(for: lang ?? picker?.lang ?? "en")
        await load()
    }

    public func setLabelStyle(_ style: LabelStyle?) {
        var p = preferences
        p.labelStyle = style
        preferences = p
        preferencesStore.save(p)
    }

    // MARK: - Opening a meet (P-08)

    public func open(_ meet: MeetSummary) async throws -> MeetContext {
        let config = try await api.meetConfig(meet.id)
        let title = config.appWindowTitle.isEmpty ? (config.name.isEmpty ? meet.name : config.name) : config.appWindowTitle
        return MeetContext(api: api, kind: .cloud, meetID: meet.id, title: title, settings: config.settings,
                           stringsLoader: stringsLoader, preferences: preferences, vidStore: vidStore,
                           connector: connector)
    }

    /// A Pi has one meet and no picker: straight to the board.
    public func openPi() async throws -> MeetContext {
        let config = try await api.piConfig()
        return MeetContext(api: api, kind: .pi, meetID: nil, title: config.meetTitle, settings: config.settings,
                           stringsLoader: stringsLoader, preferences: preferences, vidStore: vidStore,
                           connector: connector)
    }

    static func notice(for info: ServerInfo) -> String? {
        let expected = ServerInfo.expectedContract
        var parts: [String] = []
        if info.contract.api != expected.api { parts.append("api \(info.contract.api) \u{2260} \(expected.api)") }
        if info.contract.app != expected.app { parts.append("app \(info.contract.app) \u{2260} \(expected.app)") }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
    }

    private func refreshStrings() async {
        let lang = preferences.language ?? picker?.lang ?? strings.language
        strings = stringsLoader.table(for: lang)
        if let fresh = await stringsLoader.refresh(lang) { strings = fresh }
    }
}
