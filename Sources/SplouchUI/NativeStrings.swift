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
    static var done: String { String(localized: "done", bundle: .module) }
    static var ok: String { String(localized: "ok", bundle: .module) }
    static var retry: String { String(localized: "retry", bundle: .module) }
    static var remove: String { String(localized: "remove", bundle: .module) }
    static var checking: String { String(localized: "checking", bundle: .module) }
    static var openBoard: String { String(localized: "open_board", bundle: .module) }
    static var meetGone: String { String(localized: "meet_gone", bundle: .module) }
    static var serverUnreachable: String { String(localized: "server_unreachable", bundle: .module) }
    static var notSplouch: String { String(localized: "not_splouch", bundle: .module) }
    static var invalidAddress: String { String(localized: "invalid_address", bundle: .module) }
    // P-15. Light and dark are about the device, not about anything a web page
    // shows, so the words are the app's (T-05) and the server serves none.
    static var appearance: String { String(localized: "appearance", bundle: .module) }
    static var appearanceDark: String { String(localized: "appearance_dark", bundle: .module) }
    static var appearanceLight: String { String(localized: "appearance_light", bundle: .module) }
    static var appearanceAuto: String { String(localized: "appearance_auto", bundle: .module) }
}
