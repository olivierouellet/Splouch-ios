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
    public private(set) var colors: ThemeColors
    public private(set) var fonts: ThemeFonts
    /// nil until loaded; empty `heats` is "loaded, no schedule yet" (S-07).
    public private(set) var schedule: Schedule?
    public private(set) var scheduleFailed = false
    /// True against a Pi: api.md §4 gives a Pi no schedule JSON.
    public let scheduleUnavailable: Bool
    /// Session-only (S-20).
    public var filter = ScheduleFilter()
    /// A-09: the meet is gone from this server.
    public private(set) var gone = false
    public private(set) var refreshing = false

    /// The device's choices, applied over the meet's locale (T-06).
    public private(set) var language: String?
    public private(set) var labelStyle: LabelStyle?

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
        self.labelStyle = preferences.labelStyle
        self.scheduleUnavailable = kind == .pi
        self.session = MeetSession(address: api.address, kind: kind, meetID: meetID, settings: settings,
                                   vidStore: vidStore, connector: connector, timing: timing)
        let lang = preferences.language ?? settings.locale
        self.strings = stringsLoader.table(for: lang)
        self.labels = [:]
        self.colors = ThemeColors(settings.themeColors)
        self.fonts = ThemeFonts(settings.themeFonts)
        self.labels = LabelResolver.labels(settings: settings, language: preferences.language,
                                           style: preferences.labelStyle, table: strings)
        session.onReload = { [weak self] in Task { await self?.refresh() } }
        session.onScheduleUpdate = { [weak self] in Task { await self?.loadSchedule() } }
    }

    /// The language the tabs render in.
    public var effectiveLanguage: String { language ?? settings.locale }
    public var effectiveLabelStyle: LabelStyle { labelStyle ?? (settings.labelStyle == "long" ? .long : .short) }
    public var currentHeat: HeatRef? { session.currentHeat }

    /// Opens the sockets, loads the schedule, revalidates the strings.
    public func start() {
        session.start()
        Task { await loadSchedule() }
        Task { await refreshStrings() }
    }

    public func stop() async {
        await session.stop()
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
                apply(settings: config.settings)
            case .pi:
                let config = try await api.piConfig()
                title = config.meetTitle
                apply(settings: config.settings)
            }
        } catch APIError.notFound {
            gone = true
            return
        } catch {
            // Unreachable: keep drawing what we have; the sockets carry on.
        }
        await loadSchedule()
        await refreshStrings()
    }

    public func loadSchedule() async {
        guard kind == .cloud, let meetID else { return }
        do {
            let s = try await api.schedule(meetID: meetID)
            schedule = s
            scheduleFailed = false
            filter.prune(to: s.heats)
        } catch APIError.notFound {
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

    public func setLabelStyle(_ style: LabelStyle?) {
        labelStyle = style
        rebuildLabels()
    }

    /// T-11: the event name in the reader's language when the parts allow it.
    public func eventName(_ name: String, parts: EventNameParts?) -> String {
        EventName.resolve(eventName: name, parts: parts, vocab: strings.eventVocabulary)
    }

    // MARK: - Private

    private func apply(settings new: MeetSettings) {
        settings = new
        colors = ThemeColors(new.themeColors)
        fonts = ThemeFonts(new.themeFonts)
        if language == nil, strings.language != new.locale {
            strings = stringsLoader.table(for: new.locale)
        }
        rebuildLabels()
        session.apply(settings: new)
    }

    private func rebuildLabels() {
        labels = LabelResolver.labels(settings: settings, language: language, style: labelStyle, table: strings)
    }

    private func refreshStrings() async {
        let lang = effectiveLanguage
        if let fresh = await stringsLoader.refresh(lang), fresh.language == effectiveLanguage {
            strings = fresh
            rebuildLabels()
        }
    }
}
