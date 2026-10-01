import Foundation

/// The words the app owns (app.md T-05): about the app or the device, not what a
/// web page shows. Translated natively in `Resources/Localizable.xcstrings`;
/// everything a spectator reads that the server also renders comes from
/// `StringTable.mobile` instead.
enum Native {
    static var server: String { String(localized: "server", bundle: .module) }
    static var addServer: String { String(localized: "add_server", bundle: .module) }
    static var serverPlaceholder: String { String(localized: "server_placeholder", bundle: .module) }
    static var nearby: String { String(localized: "nearby", bundle: .module) }
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
}
