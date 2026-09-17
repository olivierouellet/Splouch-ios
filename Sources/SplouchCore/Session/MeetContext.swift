import Foundation
import Observation

/// Everything the app shell needs for one open meet: the session, the config
/// it renders with, its strings and labels, and the schedule. Owns the refresh
/// paths — pull-to-refresh (A-05), `reload` (C-08), `schedule_update` (S-21) —
/// and the one signal that sends the user back to the picker (A-09).
@MainActor
@Observable
public final class MeetContext {
    public let api: SplouchAPI
    public let session: MeetSession
    public let kind: ServerKind
    public let meetID: String?
    private let stringsLoader: StringsLoader

    /// The meet's name for the shell header.
    public private(set) var title: String
    public private(set) var settings: MeetSettings
    public private(set) var strings: StringTable
    public private(set) var labels: [String: String]
    /// The same table in its short forms — `EV` / `HT`, `ÉP` / `SÉR`. The board's
    /// column headers want the long words (T-04), but the Schedule tab repeats
    /// "Event N — Heat M" once per card, where the short pair says the same
    /// thing and leaves the width for the event name and the scheduled time.
    public private(set) var shortLabels: [String: String]
    public private(set) var fonts: ThemeFonts
    /// nil until loaded; empty `heats` is "loaded, no schedule yet" (S-07).
    public private(set) var schedule: Schedule?
    public private(set) var scheduleFailed = false
    /// S-09's typeahead index, built off the start list above — no request.
    /// Rebuilt with every re-fetch (S-21).
    public private(set) var suggestions = SuggestionIndex()
    /// Session-only (S-20).
    public var filter = ScheduleFilter()
    /// A-09: the meet is gone from this server.
    public private(set) var gone = false
    public private(set) var refreshing = false

    /// The device's choices, applied over the meet's locale (T-06).
    public private(set) var language: String?
    public private(set) var labelStyle: LabelStyle

    public init(api: SplouchAPI, kind: ServerKind, meetID: String?, title: String, settings: MeetSettings,
                stringsLoader: StringsLoader, preferences: Preferences, vidStore: any VidStore,
                connector: any WebSocketConnector = URLSessionWebSocketConnector(),
                timing: SocketTiming = .standard) {
        self.api = api
        self.kind = kind
        self.meetID = kind == .cloud ? meetID : nil
        self.title = title
        self.settings = settings
        self.stringsLoader = stringsLoader
        self.language = preferences.language
        self.labelStyle = preferences.effectiveLabelStyle
        self.session = MeetSession(address: api.address, kind: kind, meetID: meetID, settings: settings,
                                   vidStore: vidStore, connector: connector, timing: timing)
        let lang = preferences.language ?? settings.locale
        self.strings = stringsLoader.table(for: lang)
        self.labels = [:]
        self.shortLabels = [:]
        self.fonts = ThemeFonts(settings.themeFonts)
        self.labels = LabelResolver.labels(settings: settings, language: preferences.language,
                                           style: preferences.effectiveLabelStyle, table: strings)
        self.shortLabels = LabelResolver.labels(settings: settings, language: preferences.language,
                                                style: .short, table: strings)
        session.onReload = { [weak self] in Task { await self?.refresh() } }
        session.onScheduleUpdate = { [weak self] in Task { await self?.loadSchedule() } }
        session.onReconnected = { [weak self] in Task { await self?.checkMeet() } }
    }

    /// The language the tabs render in.
    public var effectiveLanguage: String { language ?? settings.locale }
    public var effectiveLabelStyle: LabelStyle { labelStyle }
    public var currentHeat: HeatRef? { session.currentHeat }

    /// A-11: a meet with no timing console has no Results tab at all. Read off
    /// `settings`, which every config fetch replaces — `checkMeet()` on
    /// reconnect and foreground, `refresh()` on pull-to-refresh and `reload` —
    /// so an operator who plugs a console in mid-meet, or unplugs one, is
    /// followed live without a restart. The key is never consulted: `timed` is
    /// the whole question (api.md §5.4).
    public var showsResults: Bool { settings.console.timed }

    /// Opens the sockets, loads the schedule, revalidates the strings.
    public func start() {
        session.start()
        Task { await loadSchedule() }
        Task { await refreshStrings() }
    }

    public func stop() async {
        await session.stop()
    }

    /// Foreground: probe the sockets (C-05) and ask whether the meet is still
    /// there (A-09).
    public func foregrounded() {
        session.wake()
        Task { await checkMeet() }
    }

    /// A-09: on a cloud, `GET /meet/{id}/config` is the check; 404 means gone.
    /// Any other failure is a network fault the sockets already handle. A Pi has
    /// one meet that cannot go away.
    public func checkMeet() async {
        guard kind == .cloud, let meetID else { return }
        do {
            let config = try await api.meetConfig(meetID)
            title = config.appWindowTitle.isEmpty ? config.name : config.appWindowTitle
            apply(settings: config.settings, rejoin: false)
        } catch APIError.notFound {
            gone = true
        } catch {}
    }

    /// A-05 and C-08: re-fetch config, redraw, re-join. A 404 means the meet is
    /// gone (A-09).
    public func refresh() async {
        refreshing = true
        defer { refreshing = false }
        do {
            switch kind {
            case .cloud:
                guard let meetID else { return }
                let config = try await api.meetConfig(meetID)
                title = config.appWindowTitle.isEmpty ? config.name : config.appWindowTitle
                apply(settings: config.settings, rejoin: true)
            case .pi:
                let config = try await api.piConfig()
                title = config.meetTitle
                apply(settings: config.settings, rejoin: true)
            }
        } catch APIError.notFound where kind == .cloud {
            gone = true
            return
        } catch {
            // Unreachable, or a Pi answering oddly: keep drawing what we have;
            // the sockets carry on (a Pi's one meet cannot go away, §0.2).
        }
        await loadSchedule()
        await refreshStrings()
    }

    /// The start list: `GET /meet/{id}/schedule` on a cloud, `GET /schedule.json`
    /// on a Pi — the same body (api.md §5.8).
    public func loadSchedule() async {
        do {
            let s: Schedule
            switch kind {
            case .cloud:
                guard let meetID else { return }
                s = try await api.schedule(meetID: meetID)
            case .pi:
                s = try await api.piSchedule()
            }
            schedule = s
            scheduleFailed = false
            suggestions = SuggestionIndex(heats: s.heats)
            // Keep the chips the new list can still match (S-20 lives on).
            filter.prune(to: s.heats)
        } catch APIError.notFound where kind == .cloud {
            gone = true
        } catch {
            scheduleFailed = schedule == nil
        }
    }

    public func setLanguage(_ lang: String?) {
        language = lang
        strings = stringsLoader.table(for: effectiveLanguage)
        rebuildLabels()
        Task { await refreshStrings() }
    }

    public func setLabelStyle(_ style: LabelStyle) {
        labelStyle = style
        rebuildLabels()
    }

    /// T-11: the event name in the reader's language when the parts allow it.
    public func eventName(_ name: String, parts: EventNameParts?) -> String {
        EventName.resolve(eventName: name, parts: parts, vocab: strings.eventVocabulary)
    }

    // MARK: - Private

    private func apply(settings new: MeetSettings, rejoin: Bool) {
        let changed = new != settings
        settings = new
        fonts = ThemeFonts(new.themeFonts)
        if language == nil, strings.language != new.locale {
            strings = stringsLoader.table(for: new.locale)
        }
        rebuildLabels()
        if rejoin || changed { session.apply(settings: new) }
    }

    private func rebuildLabels() {
        labels = LabelResolver.labels(settings: settings, language: language, style: labelStyle, table: strings)
        shortLabels = LabelResolver.labels(settings: settings, language: language, style: .short, table: strings)
    }

    private func refreshStrings() async {
        let lang = effectiveLanguage
        if let fresh = await stringsLoader.refresh(lang), fresh.language == effectiveLanguage {
            strings = fresh
            rebuildLabels()
        }
    }
}
