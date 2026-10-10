import Foundation
import SplouchCore

/// The words the app owns (app.md T-05): about the app or the device, not what a
/// web page shows. Translated natively in `Resources/Localizable.xcstrings`;
/// everything a spectator reads that the server also renders comes from
/// `StringTable.mobile` instead.
enum Native {
    static var server: String { String(localized: "server", bundle: .module) }
    static var addServer: String { String(localized: "add_server", bundle: .module) }
    static var serverPlaceholder: String { String(localized: "server_placeholder", bundle: .module) }
    // P-12. The browse runs only when asked, so the section names who it is for
    // and carries its own button and its own empty answer.
    static var localServer: String { String(localized: "local_server", bundle: .module) }
    static var localSearch: String { String(localized: "local_search", bundle: .module) }
    static var localSearchAgain: String { String(localized: "local_search_again", bundle: .module) }
    static var localNoneFound: String { String(localized: "local_none_found", bundle: .module) }
    static var cancel: String { String(localized: "cancel", bundle: .module) }
    static var ok: String { String(localized: "ok", bundle: .module) }
    static var retry: String { String(localized: "retry", bundle: .module) }
    static var remove: String { String(localized: "remove", bundle: .module) }
    static var serverRemoved: String { String(localized: "server_removed", bundle: .module) }
    static var undo: String { String(localized: "undo", bundle: .module) }
    static var checking: String { String(localized: "checking", bundle: .module) }
    static var openBoard: String { String(localized: "open_board", bundle: .module) }
    static var meetGone: String { String(localized: "meet_gone", bundle: .module) }
    static var serverUnreachable: String { String(localized: "server_unreachable", bundle: .module) }
    static var notSplouch: String { String(localized: "not_splouch", bundle: .module) }
    static var invalidAddress: String { String(localized: "invalid_address", bundle: .module) }
    // P-16. A scanned code's prompt: the question, the two buttons that answer it,
    // and the ways a printed link can be wrong. All of it is about this device and
    // the link it was handed, so none of it comes from a server (T-05).
    static var addServerQuestion: String { String(localized: "add_server_question", bundle: .module) }
    static var switchServerQuestion: String { String(localized: "switch_server_question", bundle: .module) }
    static var alreadyOnServer: String { String(localized: "already_on_server", bundle: .module) }
    static var cannotAddServer: String { String(localized: "cannot_add_server", bundle: .module) }
    static var add: String { String(localized: "add", bundle: .module) }
    static var switchTo: String { String(localized: "switch_to", bundle: .module) }
    static var badServerLink: String { String(localized: "bad_server_link", bundle: .module) }
    static var cleartextNotLocal: String { String(localized: "cleartext_not_local", bundle: .module) }
    // P-15 and T-08. The picker menu's own settings: shown before any server
    // answers, so the words are the app's (T-05) even though the web picker has
    // its own served copy of each.
    static var appearance: String { String(localized: "appearance", bundle: .module) }
    static var appearanceDark: String { String(localized: "appearance_dark", bundle: .module) }
    static var appearanceLight: String { String(localized: "appearance_light", bundle: .module) }
    static var appearanceAuto: String { String(localized: "appearance_auto", bundle: .module) }
    static var language: String { String(localized: "language", bundle: .module) }
    static var languageAuto: String { String(localized: "language_auto", bundle: .module) }
    static var done: String { String(localized: "done", bundle: .module) }
    // P-19, P-07. Settings and its sections are the app's words (T-05); the
    // web reads its own copies from the server.
    static var settings: String { String(localized: "settings", bundle: .module) }
    static var settingsDisplay: String { String(localized: "settings_display", bundle: .module) }
    static var settingsPrivacy: String { String(localized: "settings_privacy", bundle: .module) }
    static var settingsAbout: String { String(localized: "settings_about", bundle: .module) }
    static var privacyCount: String { String(localized: "privacy_count", bundle: .module) }
    static var privacyPolicy: String { String(localized: "privacy_policy", bundle: .module) }
    static var appVersion: String { String(localized: "app_version", bundle: .module) }
    // P-20. The first and last pages carry the server's text; titles, the pages
    // between, and the controls are the app's.
    static var showIntroduction: String { String(localized: "show_introduction", bundle: .module) }
    static var introSkip: String { String(localized: "intro_skip", bundle: .module) }
    static var introNext: String { String(localized: "intro_next", bundle: .module) }
    static var introStart: String { String(localized: "intro_start", bundle: .module) }
    static var introResultsTitle: String { String(localized: "intro_results_title", bundle: .module) }
    static var introMeetsTitle: String { String(localized: "intro_meets_title", bundle: .module) }
    static var introMeetsBody: String { String(localized: "intro_meets_body", bundle: .module) }
    static var introTabsTitle: String { String(localized: "intro_tabs_title", bundle: .module) }
    static var introTabsBody: String { String(localized: "intro_tabs_body", bundle: .module) }
    static var introKeyLane: String { String(localized: "intro_key_lane", bundle: .module) }
    static var introKeyClub: String { String(localized: "intro_key_club", bundle: .module) }
    static var introKeyTime: String { String(localized: "intro_key_time", bundle: .module) }
    static var introKeyGap: String { String(localized: "intro_key_gap", bundle: .module) }
    static var introKeyLaps: String { String(localized: "intro_key_laps", bundle: .module) }
    static var introKeyPlace: String { String(localized: "intro_key_place", bundle: .module) }
    static var introTimesTitle: String { String(localized: "intro_times_title", bundle: .module) }
    static var introTimesBody: String { String(localized: "intro_times_body", bundle: .module) }
    static var introFollowTitle: String { String(localized: "intro_follow_title", bundle: .module) }
    static var introFollowBody: String { String(localized: "intro_follow_body", bundle: .module) }
    static var introCountingTitle: String { String(localized: "intro_counting_title", bundle: .module) }
    static var privacyWhere: String { String(localized: "privacy_where", bundle: .module) }
    // N-01 to N-04. App-only — the web has no notifications — so every word is
    // the app's (T-05), not the server's.
    static var notifications: String { String(localized: "notifications", bundle: .module) }
    static var notifySwimmers: String { String(localized: "notify_swimmers", bundle: .module) }
    static var notifyAdd: String { String(localized: "notify_add", bundle: .module) }
    static var notifyNone: String { String(localized: "notify_none", bundle: .module) }
    static var notifyBefore: String { String(localized: "notify_before", bundle: .module) }
    static var notifyByMinutes: String { String(localized: "notify_by_minutes", bundle: .module) }
    static var notifyByHeats: String { String(localized: "notify_by_heats", bundle: .module) }
    static var notifyWhen: String { String(localized: "notify_when", bundle: .module) }
    static var notifySelected: String { String(localized: "notify_selected", bundle: .module) }
    static var notifySelectedFooter: String { String(localized: "notify_selected_footer", bundle: .module) }
    static var notifyEnabled: String { String(localized: "notify_enabled", bundle: .module) }
    static var notifyPaused: String { String(localized: "notify_paused", bundle: .module) }
    static var notifyPrivacy: String { String(localized: "notify_privacy", bundle: .module) }
    static var notifyDenied: String { String(localized: "notify_denied", bundle: .module) }
    static var notifyOpenSettings: String { String(localized: "notify_open_settings", bundle: .module) }
    static var notifyTheseSwimmers: String { String(localized: "notify_these_swimmers", bundle: .module) }
    static func notifyLead(_ lead: FollowLead) -> String {
        switch lead {
        case .minutes(let n): String(format: String(localized: "notify_minutes_value", bundle: .module), n)
        case .heats(1): String(localized: "notify_heat_value", bundle: .module)
        case .heats(let n): String(format: String(localized: "notify_heats_value", bundle: .module), n)
        }
    }
    // P-21: the picker's filter is the app's, so its words are too.
    static var meetFilter: String { String(localized: "meet_filter", bundle: .module) }
    static var filterCountry: String { String(localized: "filter_country", bundle: .module) }
    static var filterProvince: String { String(localized: "filter_province", bundle: .module) }
    static var filterClub: String { String(localized: "filter_club", bundle: .module) }
    static var filterClubLetters: String { String(localized: "filter_club_letters", bundle: .module) }
    static var filterClubLettersHint: String { String(localized: "filter_club_letters_hint", bundle: .module) }
    static var filterClubAdd: String { String(localized: "filter_club_add", bundle: .module) }
    static var filterClear: String { String(localized: "filter_clear", bundle: .module) }
    static var filterHidesAll: String { String(localized: "filter_hides_all", bundle: .module) }
    static func filterHidden(_ n: Int) -> String {
        n == 1
            ? String(localized: "filter_hidden_one", bundle: .module)
            : String(format: String(localized: "filter_hidden_other", bundle: .module), n)
    }
    static func notifyFollowing(_ n: Int) -> String {
        String(format: String(localized: "notify_following", bundle: .module), n)
    }
}
