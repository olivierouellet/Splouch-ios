import Foundation
import Observation
import SplouchCore

/// T-08: the app's own words follow the language chosen in settings, not only
/// the device's. `Native` reads `bundle` on every lookup, and a view that does
/// so in its body is redrawn when the choice changes (Observation).
@MainActor
@Observable
final class NativeLanguage {
    static let shared = NativeLanguage()
    private(set) var bundle: Bundle = .module

    /// nil → the device's language, as the system resolves it. A language the
    /// app has no table for → English (T-05). The tables are `lproj` folders
    /// only in a build Xcode compiled; elsewhere the module bundle answers.
    func set(_ lang: String?) {
        let found = lang.flatMap { Self.table($0) ?? Self.table("en") }
        bundle = found ?? .module
    }

    private static func table(_ lang: String) -> Bundle? {
        Bundle.module.path(forResource: lang, ofType: "lproj").flatMap(Bundle.init(path:))
    }
}

/// The words the app owns (app.md T-05): about the app or the device, not what a
/// web page shows. Translated natively in `Resources/Localizable.xcstrings`;
/// everything a spectator reads that the server also renders comes from
/// `StringTable.mobile` instead.
@MainActor
enum Native {
    static var server: String { String(localized: "server", bundle: NativeLanguage.shared.bundle) }
    static var addServer: String { String(localized: "add_server", bundle: NativeLanguage.shared.bundle) }
    static var serverPlaceholder: String {
        String(localized: "server_placeholder", bundle: NativeLanguage.shared.bundle)
    }
    // P-12. The browse runs only when asked, so the section names who it is for
    // and carries its own button and its own empty answer.
    static var localServer: String { String(localized: "local_server", bundle: NativeLanguage.shared.bundle) }
    static var localSearch: String { String(localized: "local_search", bundle: NativeLanguage.shared.bundle) }
    static var localSearchAgain: String {
        String(localized: "local_search_again", bundle: NativeLanguage.shared.bundle)
    }
    static var localNoneFound: String { String(localized: "local_none_found", bundle: NativeLanguage.shared.bundle) }
    static var cancel: String { String(localized: "cancel", bundle: NativeLanguage.shared.bundle) }
    static var ok: String { String(localized: "ok", bundle: NativeLanguage.shared.bundle) }
    static var retry: String { String(localized: "retry", bundle: NativeLanguage.shared.bundle) }
    static var remove: String { String(localized: "remove", bundle: NativeLanguage.shared.bundle) }
    static var serverRemoved: String { String(localized: "server_removed", bundle: NativeLanguage.shared.bundle) }
    static var undo: String { String(localized: "undo", bundle: NativeLanguage.shared.bundle) }
    static var checking: String { String(localized: "checking", bundle: NativeLanguage.shared.bundle) }
    static var openBoard: String { String(localized: "open_board", bundle: NativeLanguage.shared.bundle) }
    static var meetGone: String { String(localized: "meet_gone", bundle: NativeLanguage.shared.bundle) }
    static var serverUnreachable: String {
        String(localized: "server_unreachable", bundle: NativeLanguage.shared.bundle)
    }
    static var notSplouch: String { String(localized: "not_splouch", bundle: NativeLanguage.shared.bundle) }
    static var invalidAddress: String { String(localized: "invalid_address", bundle: NativeLanguage.shared.bundle) }
    // P-16. A scanned code's prompt: the question, the two buttons that answer it,
    // and the ways a printed link can be wrong. All of it is about this device and
    // the link it was handed, so none of it comes from a server (T-05).
    static var addServerQuestion: String {
        String(localized: "add_server_question", bundle: NativeLanguage.shared.bundle)
    }
    static var switchServerQuestion: String {
        String(localized: "switch_server_question", bundle: NativeLanguage.shared.bundle)
    }
    static var alreadyOnServer: String { String(localized: "already_on_server", bundle: NativeLanguage.shared.bundle) }
    static var cannotAddServer: String { String(localized: "cannot_add_server", bundle: NativeLanguage.shared.bundle) }
    static var add: String { String(localized: "add", bundle: NativeLanguage.shared.bundle) }
    static var switchTo: String { String(localized: "switch_to", bundle: NativeLanguage.shared.bundle) }
    static var badServerLink: String { String(localized: "bad_server_link", bundle: NativeLanguage.shared.bundle) }
    static var cleartextNotLocal: String {
        String(localized: "cleartext_not_local", bundle: NativeLanguage.shared.bundle)
    }
    // P-15 and T-08. The picker menu's own settings: shown before any server
    // answers, so the words are the app's (T-05) even though the web picker has
    // its own served copy of each.
    static var appearance: String { String(localized: "appearance", bundle: NativeLanguage.shared.bundle) }
    static var appearanceDark: String { String(localized: "appearance_dark", bundle: NativeLanguage.shared.bundle) }
    static var appearanceLight: String { String(localized: "appearance_light", bundle: NativeLanguage.shared.bundle) }
    static var appearanceAuto: String { String(localized: "appearance_auto", bundle: NativeLanguage.shared.bundle) }
    static var language: String { String(localized: "language", bundle: NativeLanguage.shared.bundle) }
    static var languageAuto: String { String(localized: "language_auto", bundle: NativeLanguage.shared.bundle) }
    static var done: String { String(localized: "done", bundle: NativeLanguage.shared.bundle) }
    // P-19, P-07. Settings and its sections are the app's words (T-05); the
    // web reads its own copies from the server.
    static var settings: String { String(localized: "settings", bundle: NativeLanguage.shared.bundle) }
    static var settingsDisplay: String { String(localized: "settings_display", bundle: NativeLanguage.shared.bundle) }
    static var settingsPrivacy: String { String(localized: "settings_privacy", bundle: NativeLanguage.shared.bundle) }
    static var settingsAbout: String { String(localized: "settings_about", bundle: NativeLanguage.shared.bundle) }
    static var privacyCount: String { String(localized: "privacy_count", bundle: NativeLanguage.shared.bundle) }
    static var privacyPolicy: String { String(localized: "privacy_policy", bundle: NativeLanguage.shared.bundle) }
    static var appVersion: String { String(localized: "app_version", bundle: NativeLanguage.shared.bundle) }
    // P-20. The first and last pages carry the server's text; titles, the pages
    // between, and the controls are the app's.
    static var showIntroduction: String { String(localized: "show_introduction", bundle: NativeLanguage.shared.bundle) }
    static var introSkip: String { String(localized: "intro_skip", bundle: NativeLanguage.shared.bundle) }
    static var introNext: String { String(localized: "intro_next", bundle: NativeLanguage.shared.bundle) }
    static var introStart: String { String(localized: "intro_start", bundle: NativeLanguage.shared.bundle) }
    static var introResultsTitle: String {
        String(localized: "intro_results_title", bundle: NativeLanguage.shared.bundle)
    }
    static var introMeetsTitle: String { String(localized: "intro_meets_title", bundle: NativeLanguage.shared.bundle) }
    static var introMeetsBody: String { String(localized: "intro_meets_body", bundle: NativeLanguage.shared.bundle) }
    static var introTabsTitle: String { String(localized: "intro_tabs_title", bundle: NativeLanguage.shared.bundle) }
    static var introTabsBody: String { String(localized: "intro_tabs_body", bundle: NativeLanguage.shared.bundle) }
    static var introKeyLane: String { String(localized: "intro_key_lane", bundle: NativeLanguage.shared.bundle) }
    static var introKeyClub: String { String(localized: "intro_key_club", bundle: NativeLanguage.shared.bundle) }
    static var introKeyTime: String { String(localized: "intro_key_time", bundle: NativeLanguage.shared.bundle) }
    static var introKeyGap: String { String(localized: "intro_key_gap", bundle: NativeLanguage.shared.bundle) }
    static var introKeyLaps: String { String(localized: "intro_key_laps", bundle: NativeLanguage.shared.bundle) }
    static var introKeyPlace: String { String(localized: "intro_key_place", bundle: NativeLanguage.shared.bundle) }
    static var introTimesTitle: String { String(localized: "intro_times_title", bundle: NativeLanguage.shared.bundle) }
    static var introTimesBody: String { String(localized: "intro_times_body", bundle: NativeLanguage.shared.bundle) }
    static var introFollowTitle: String {
        String(localized: "intro_follow_title", bundle: NativeLanguage.shared.bundle)
    }
    static var introFollowBody: String { String(localized: "intro_follow_body", bundle: NativeLanguage.shared.bundle) }
    static var introCountingTitle: String {
        String(localized: "intro_counting_title", bundle: NativeLanguage.shared.bundle)
    }
    static var privacyWhere: String { String(localized: "privacy_where", bundle: NativeLanguage.shared.bundle) }
    // N-01 to N-04. App-only — the web has no notifications — so every word is
    // the app's (T-05), not the server's.
    static var notifications: String { String(localized: "notifications", bundle: NativeLanguage.shared.bundle) }
    static var notifySwimmers: String { String(localized: "notify_swimmers", bundle: NativeLanguage.shared.bundle) }
    static var notifyAdd: String { String(localized: "notify_add", bundle: NativeLanguage.shared.bundle) }
    static var notifyNone: String { String(localized: "notify_none", bundle: NativeLanguage.shared.bundle) }
    static var notifyBefore: String { String(localized: "notify_before", bundle: NativeLanguage.shared.bundle) }
    static var notifyByMinutes: String { String(localized: "notify_by_minutes", bundle: NativeLanguage.shared.bundle) }
    static var notifyByHeats: String { String(localized: "notify_by_heats", bundle: NativeLanguage.shared.bundle) }
    static var notifyWhen: String { String(localized: "notify_when", bundle: NativeLanguage.shared.bundle) }
    static var notifySelected: String { String(localized: "notify_selected", bundle: NativeLanguage.shared.bundle) }
    static var notifySelectedFooter: String {
        String(localized: "notify_selected_footer", bundle: NativeLanguage.shared.bundle)
    }
    static var notifyEnabled: String { String(localized: "notify_enabled", bundle: NativeLanguage.shared.bundle) }
    static var notifyPaused: String { String(localized: "notify_paused", bundle: NativeLanguage.shared.bundle) }
    static var notifyPausedShort: String {
        String(localized: "notify_paused_short", bundle: NativeLanguage.shared.bundle)
    }
    static var notifyPauseAll: String { String(localized: "notify_pause_all", bundle: NativeLanguage.shared.bundle) }
    static var notifyPrivacy: String { String(localized: "notify_privacy", bundle: NativeLanguage.shared.bundle) }
    static var notifyDenied: String { String(localized: "notify_denied", bundle: NativeLanguage.shared.bundle) }
    static var notifyOpenSettings: String {
        String(localized: "notify_open_settings", bundle: NativeLanguage.shared.bundle)
    }
    static var notifyTheseSwimmers: String {
        String(localized: "notify_these_swimmers", bundle: NativeLanguage.shared.bundle)
    }
    static func notifyLead(_ lead: FollowLead) -> String {
        switch lead {
        case .minutes(let n):
            String(format: String(localized: "notify_minutes_value", bundle: NativeLanguage.shared.bundle), n)
        case .heats(1): String(localized: "notify_heat_value", bundle: NativeLanguage.shared.bundle)
        case .heats(let n):
            String(format: String(localized: "notify_heats_value", bundle: NativeLanguage.shared.bundle), n)
        }
    }
    // P-21: the picker's filter is the app's, so its words are too.
    static var meetFilter: String { String(localized: "meet_filter", bundle: NativeLanguage.shared.bundle) }
    static var filterCountry: String { String(localized: "filter_country", bundle: NativeLanguage.shared.bundle) }
    static var filterProvince: String { String(localized: "filter_province", bundle: NativeLanguage.shared.bundle) }
    static var filterClub: String { String(localized: "filter_club", bundle: NativeLanguage.shared.bundle) }
    static var filterClubLetters: String {
        String(localized: "filter_club_letters", bundle: NativeLanguage.shared.bundle)
    }
    static var filterClubLettersHint: String {
        String(localized: "filter_club_letters_hint", bundle: NativeLanguage.shared.bundle)
    }
    static var filterClubAdd: String { String(localized: "filter_club_add", bundle: NativeLanguage.shared.bundle) }
    static var filterClear: String { String(localized: "filter_clear", bundle: NativeLanguage.shared.bundle) }
    static var filterHidesAll: String { String(localized: "filter_hides_all", bundle: NativeLanguage.shared.bundle) }
    static func filterHidden(_ n: Int) -> String {
        n == 1
            ? String(localized: "filter_hidden_one", bundle: NativeLanguage.shared.bundle)
            : String(format: String(localized: "filter_hidden_other", bundle: NativeLanguage.shared.bundle), n)
    }
    static func notifyFollowing(_ n: Int) -> String {
        String(format: String(localized: "notify_following", bundle: NativeLanguage.shared.bundle), n)
    }
}
