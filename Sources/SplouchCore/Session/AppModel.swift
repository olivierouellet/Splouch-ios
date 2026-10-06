import Foundation
import Observation
import os

/// P-16: a QR code named a server, and this is the question the app has to ask before
/// anything happens. Held on `AppModel` rather than in a view, so it survives the
/// picker being rebuilt under it while the reader is still reading it.
///
/// `address` is nil when the link itself was no good: the prompt is then an apology with
/// one button, because a code that opens the app and appears to do nothing cannot be
/// told from a dead app.
public struct ServerInvite: Sendable, Equatable {
    /// Where the scanned address already stands with the app, which is the whole of what
    /// the prompt has left to ask.
    public enum Standing: Sendable, Equatable {
        /// Offered nowhere yet: the prompt asks to **add** it.
        case new
        /// Already in the list, but not the one in use: the prompt asks to **switch**.
        case listed
        /// Already the server in use, and answering. There is nothing to do, so the
        /// prompt says so over one button and asks the network **nothing** — a scan on a
        /// pool deck with bad wifi must never answer "cannot reach this server" over a
        /// live heat coming from that very server.
        ///
        /// **Only while it is answering.** A selected server whose handshake failed is
        /// `listed` instead, so scanning its code re-dials it — that is a spectator whose
        /// Pi rebooted, and the useful thing is the reconnect, not a claim that all is
        /// well while the screen behind says otherwise.
        case inUse
    }

    public var address: ServerAddress?
    public var standing: Standing
    /// `P-13`'s `GET /server` is in flight; the prompt says so and takes no second press.
    public var checking: Bool
    public var failure: InviteFailure?

    public init(
        address: ServerAddress?, standing: Standing = .new, checking: Bool = false,
        failure: InviteFailure? = nil
    ) {
        self.address = address
        self.standing = standing
        self.checking = checking
        self.failure = failure
    }

    /// Nothing to agree to: a dead link, or a server the app is already on.
    public var nothingToDo: Bool { address == nil || standing == .inUse }
}

/// Why an invite cannot be taken up. The words are the app's own (T-05) — a link and a
/// network are the device's business, not a meet's — so this names the case and the view
/// picks the string.
public enum InviteFailure: Sendable, Equatable {
    case badLink
    case cleartextNotLocal
    case notSplouch
    case unreachable
}

/// P-19: settings' sections, in the contract's order.
public enum SettingsSection: String, Sendable, CaseIterable {
    case display
    case privacy
    case server
    case about
}

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
    /// The language menu's list: the captured snapshot until a server answers,
    /// then the last successful `GET /locales`. A failed refresh keeps the
    /// previous list rather than emptying the menu (app.md T-08, T-10).
    public private(set) var locales: [LocaleEntry] = BuiltInStrings.locales
    public private(set) var loading = false
    /// The last failure reaching the server, nil when the list loaded.
    public private(set) var unreachable = false
    /// Chrome strings in the device's language.
    public private(set) var strings: StringTable
    /// P-16: the question a scanned code raised, nil when there is none on screen.
    public private(set) var invite: ServerInvite?
    /// P-14: the contract versions that differ from the ones this app was built
    /// against, as `api v1 ≠ v2`; nil when they match. A notice, never a gate.
    public private(set) var contractNotice: String?
    /// C-10: whether the spectator lets the server in use count this device,
    /// read from `vidStore` per server. Observed here because the store is not.
    public private(set) var counting = true

    public init(
        defaultServer: ServerAddress,
        preferencesStore: any PreferencesStore = UserDefaultsPreferencesStore(),
        vidStore: any VidStore = UserDefaultsVidStore(),
        bundleCache: any BundleCache = FileBundleCache.standard(),
        session: URLSession = .shared, connector: any WebSocketConnector = URLSessionWebSocketConnector()
    ) {
        self.defaultServer = defaultServer
        self.preferencesStore = preferencesStore
        self.vidStore = vidStore
        self.bundleCache = bundleCache
        self.session = session
        self.connector = connector
        let prefs = preferencesStore.load()
        self.preferences = prefs
        self.server = prefs.server ?? defaultServer
        self.counting = vidStore.counting(for: (prefs.server ?? defaultServer).origin)
        self.strings = BuiltInStrings.table(
            for: prefs.language ?? Locale.current.language.languageCode?.identifier ?? "en")
    }

    public var api: SplouchAPI { SplouchAPI(address: server, session: session) }
    /// By origin, so any spelling of the default — `https://SPLOUCH.org/` — is it.
    public var isDefaultServer: Bool { server.origin == defaultServer.origin }
    /// P-11: the picker names its server only when it is not the default — on the
    /// default there is nothing to explain. A meet does the same (`MeetShell`).
    public var namesServer: Bool { !isDefaultServer }
    public var isPi: Bool { serverInfo?.kind == .pi }
    /// The name to show in the header when the server is not the default.
    public var serverName: String { serverInfo?.name ?? server.host }
    public var stringsLoader: StringsLoader { StringsLoader(api: api, cache: bundleCache) }

    /// P-19's order: Display, Privacy, Server, About — the reader's own choices
    /// first, the server for the few who follow a pool's own. Privacy only while
    /// the server counts (P-07).
    public var settingsSections: [SettingsSection] {
        SettingsSection.allCases.filter { $0 != .privacy || analyticsEnabled }
    }

    /// The handshake, then the picker (cloud) or nothing more (Pi).
    public func start() async {
        await load()
    }

    /// P-09 / picker load: `GET /server`, then `/picker/config`, `/meets`,
    /// `/servers`, `/locales`.
    private static let log = Logger(subsystem: "app.splouch", category: "AppModel")

    public func load() async {
        loading = true
        defer {
            loading = false
            Self.log.info("load finished unreachable=\(self.unreachable) meets=\(self.meets.count)")
        }
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
                meetListReachable = true
                directory = (try? await api.servers().servers) ?? []
            } else {
                picker = nil
                meets = []
                directory = []
            }
            if let fresh = try? await api.locales(), !fresh.isEmpty { locales = fresh }
            await refreshStrings()
        } catch {
            Self.log.error("load failed: \(String(describing: error))")
            unreachable = true
        }
    }

    // MARK: - Disclaimer and privacy (P-06, P-07)

    /// P-06's full text, nil until this server's `GET /picker/config` has
    /// answered: it is that server's words about its results, never a
    /// snapshot's copy of another's.
    public var disclaimer: String? { served("results_disclaimer") }

    /// P-06's one line. Shown only beside `disclaimer`; an older server that
    /// predates the short key falls back through `mobile` (T-10).
    public var disclaimerShort: String? {
        guard disclaimer != nil else { return nil }
        if let short = served("results_disclaimer_short") { return short }
        let fallback = strings.mobile("results_disclaimer_short")
        return fallback.isEmpty ? nil : fallback
    }

    /// P-07: counting is on for this server. While it is off there is nothing
    /// to refuse, so settings show no Privacy section — the stored choice stays.
    public var analyticsEnabled: Bool { picker?.analyticsEnabled ?? false }

    /// P-07's note, nil while this server is not counting.
    public var privacyNote: String? { analyticsEnabled ? served("privacy_note") : nil }

    /// P-07, P-19: the server's own policy page.
    public var privacyPolicyURL: URL { server.endpoint("privacy") }

    private func served(_ key: String) -> String? {
        guard let text = picker?.strings[key], !text.isEmpty else { return nil }
        return text
    }

    /// C-10: the spectator's say, for the server in use only. Off deletes that
    /// server's `vid` at once; on makes a new one at the next `join_meet`.
    public func setCounting(_ on: Bool) {
        vidStore.setCounting(on, for: server.origin)
        counting = vidStore.counting(for: server.origin)
    }

    // MARK: - Introduction (P-20)

    /// P-20: first launch, once the server has answered `GET /picker/config` —
    /// pages 1 and 4 are its words, so an offline first launch postpones it to
    /// a launch that gets them.
    public var introDue: Bool { !preferences.introSeen && picker != nil }

    /// P-20: finished or skipped, which are the same thing here. Counting is
    /// left as it was either way (`C-10`'s default is not a consent).
    public func finishIntro() {
        guard !preferences.introSeen else { return }
        var p = preferences
        p.introSeen = true
        preferences = p
        preferencesStore.save(p)
    }

    // MARK: - Servers (P-11, P-13)

    /// P-13: a typed address must answer `GET /server` before it is saved, and is
    /// held to P-12's cleartext floor before it is dialled, as a scanned one is.
    public func probe(typed: String) async throws -> (ServerAddress, ServerInfo) {
        guard let address = ServerAddress(typed: typed) else { throw APIError.invalidAddress }
        guard !address.isCleartextToNonLocal else { throw APIError.cleartextNotLocal }
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

    /// P-13. Returns what it took away, or nil if there was nothing to take:
    /// removing a hand-added server is one swipe, so it has to be undoable, and
    /// an undo that cannot put the row back where it was is not one.
    @discardableResult
    public func removeSavedServer(_ saved: SavedServer) -> RemovedServer? {
        guard let index = preferences.savedServers.firstIndex(where: { $0.id == saved.id }) else { return nil }
        var p = preferences
        let removed = p.savedServers.remove(at: index)
        p.savedServers.removeAll { $0.id == saved.id }
        preferences = p
        preferencesStore.save(p)
        return RemovedServer(server: removed, index: index)
    }

    /// The inverse of `removeSavedServer`: the row goes back at its own index.
    /// No `GET /server` — it answered once when it was added (P-13), and undoing
    /// a slip on a pool deck's network is not the moment to ask again.
    public func restoreSavedServer(_ removed: RemovedServer) {
        guard !preferences.savedServers.contains(where: { $0.id == removed.server.id }) else { return }
        var p = preferences
        p.savedServers.insert(removed.server, at: min(removed.index, p.savedServers.count))
        preferences = p
        preferencesStore.save(p)
    }

    public func switchServer(_ address: ServerAddress) async {
        server = address
        serverInfo = nil
        contractNotice = nil
        meetListReachable = true
        meets = []
        picker = nil
        counting = vidStore.counting(for: address.origin)
        var p = preferences
        p.server = address.origin == defaultServer.origin ? nil : address
        preferences = p
        preferencesStore.save(p)
        await load()
    }

    // MARK: - Added by QR code (P-16)

    /// A universal link arrived. **This asks and does nothing else** — no save, no
    /// select, and no request to the address either, since scanning a code is not
    /// consent to dial whatever it names. `acceptInvite` is where `P-13`'s handshake
    /// runs.
    ///
    /// A link that does not parse still raises the prompt, carrying `badLink` or
    /// `cleartextNotLocal`: the reader scanned something, and the one outcome worse than
    /// a code that fails is a code that opens the app and appears to do nothing.
    public func openServerLink(_ url: String) {
        switch ServerLink.parse(url, host: defaultServer.host) {
        case .ok(let address):
            invite = ServerInvite(address: address, standing: standing(for: address))
        case .cleartextNotLocal:
            invite = ServerInvite(address: nil, failure: .cleartextNotLocal)
        case .invalid:
            invite = ServerInvite(address: nil, failure: .badLink)
        }
    }

    public func dismissInvite() {
        invite = nil
    }

    /// The reader said yes: run `P-13` — `GET /server`, then save, then select — and
    /// leave the prompt standing while it does, so a Pi that has gone off the network
    /// says so *there*, retryably, rather than closing and leaving the picker looking
    /// untouched.
    ///
    /// Synchronous, with the `Task` inside: `checking` lands the moment this is called,
    /// and the prompt is put back up by that change (`SplouchRootView`). The awaiting is
    /// the handshake's, not the caller's.
    ///
    /// A server already in use has no yes to give. The guard is here rather than in the
    /// view, so the single button is a property of the model.
    public func acceptInvite() {
        guard let invite, let address = invite.address, !invite.checking, invite.standing != .inUse else { return }
        self.invite = ServerInvite(address: address, standing: invite.standing, checking: true)
        Task { await self.accept(address, standing: invite.standing) }
    }

    /// `GET /server` first — the same handshake a typed address gets (P-13) — and only
    /// then save and select.
    func accept(_ address: ServerAddress, standing: ServerInvite.Standing) async {
        do {
            let info = try await SplouchAPI(address: address, session: session).server()
            // The reader is still allowed a no while this runs, and on iOS they have
            // one: an alert button cannot be disabled out from under a finger the way
            // the Android dialog's is. So the yes is only spent if the prompt that
            // gave it is still the prompt on screen — a cancel mid-handshake, or a
            // second code scanned over the first, must not switch the server anyway.
            guard invite?.address == address else { return }
            invite = nil
            await addServer(address, info: info)
        } catch {
            // Only if the prompt is still the one that asked: a reader who cancelled
            // mid-handshake, or scanned a second code, does not get this answer over it.
            guard invite?.address == address else { return }
            invite = ServerInvite(address: address, standing: standing, failure: Self.failure(for: error))
        }
    }

    static func failure(for error: any Error) -> InviteFailure {
        switch error {
        case APIError.invalidAddress: return .badLink
        case APIError.cleartextNotLocal: return .cleartextNotLocal
        case APIError.notASplouchServer, APIError.notFound, APIError.notJSON: return .notSplouch
        default: return .unreachable
        }
    }

    /// In use only while the server is *answering* — a selected server whose handshake
    /// failed is `listed`, and scanning its code re-dials it.
    private func standing(for address: ServerAddress) -> ServerInvite.Standing {
        if address == server && serverInfo != nil { return .inUse }
        return knownServers.contains { $0.address == address } ? .listed : .new
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
            // P-12: a directory entry is held to the same floor as a typed one.
            if let a = ServerAddress(typed: e.url), !a.isCleartextToNonLocal {
                add(SavedServer(name: e.name, address: a))
            }
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

    /// P-15. Device-local and immediate: nothing is re-fetched, the window just
    /// redraws in the chosen scheme.
    public func setAppearance(_ appearance: Appearance) {
        var p = preferences
        p.appearance = appearance
        preferences = p
        preferencesStore.save(p)
    }

    public func setLabelStyle(_ style: LabelStyle) {
        var p = preferences
        p.labelStyle = style
        preferences = p
        preferencesStore.save(p)
    }

    // MARK: - Opening a meet (P-08)

    /// The meet is opened at its own `base` (C-11) — config here, then its
    /// sockets and schedule in `MeetContext` — and the server's address when the
    /// list sent none. A config naming yet another `base` is followed (C-12).
    /// Strings, the picker image and the `vid` stay with the list's server.
    public func open(_ meet: MeetSummary) async throws -> MeetContext {
        var base = meet.base ?? server
        var config = try await api.at(base).meetConfig(meet.id)
        if let moved = config.base, moved != base {
            base = moved
            config = try await api.at(base).meetConfig(meet.id)
        }
        let title =
            config.appWindowTitle.isEmpty ? (config.name.isEmpty ? meet.name : config.name) : config.appWindowTitle
        return MeetContext(
            api: api, base: base, kind: .cloud, meetID: meet.id, title: title, settings: config.settings,
            stringsLoader: stringsLoader, preferences: preferences, vidStore: vidStore,
            connector: connector)
    }

    /// A Pi has one meet and no picker: straight to the board.
    public func openPi() async throws -> MeetContext {
        let config = try await api.piConfig()
        return MeetContext(
            api: api, kind: .pi, meetID: nil, title: config.meetTitle, settings: config.settings,
            stringsLoader: stringsLoader, preferences: preferences, vidStore: vidStore,
            connector: connector)
    }

    // MARK: - Leaving a meet (A-12)

    /// A-12: whether the meet list answered the last time it was asked. False
    /// keeps a spectator in their meet — the worker serving it may be fine
    /// while the list is not — and `MeetShell` shows `mobile.picker_unavailable`
    /// on back instead of popping to an empty, failing picker.
    public private(set) var meetListReachable = true
    /// How long the list gets to answer (app.md A-12: ~4 s).
    public var meetListTimeout: Duration = .seconds(4)

    /// A-12: `GET /meets`, given `meetListTimeout`. On an answer the picker's
    /// list is replaced, so the way back lands on fresh meets; on a failure or
    /// a timeout the list on hand is left exactly as it was. A Pi has no list
    /// and is always reachable for this purpose.
    @discardableResult
    public func checkMeetList() async -> Bool {
        guard serverInfo?.kind != .pi else { return true }
        let api = self.api
        let fresh: [MeetSummary]? = await withTaskGroup(of: [MeetSummary]?.self) { group in
            group.addTask { try? await api.meets() }
            let limit = meetListTimeout
            group.addTask {
                try? await Task.sleep(for: limit)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        guard api.address == server else { return meetListReachable }  // switched meanwhile
        if let fresh {
            meets = fresh
            unreachable = false
            meetListReachable = true
        } else {
            meetListReachable = false
        }
        return meetListReachable
    }

    // MARK: - Picker layout (P-18)

    /// P-18: above this many meets the picker lists compact rows with no image.
    public static let compactListThreshold = 10

    /// P-18: the whole list's count decides, not what a search leaves.
    public var listIsCompact: Bool { meets.count > Self.compactListThreshold }

    /// P-02 under P-18: the picker image to load for `meet`, nil when it has
    /// none or the list is long — and then none is fetched at all.
    public func pickerImageURL(for meet: MeetSummary) -> URL? {
        guard meet.hasPickerImage, !listIsCompact else { return nil }
        return api.pickerImageURL(meetID: meet.id)
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
