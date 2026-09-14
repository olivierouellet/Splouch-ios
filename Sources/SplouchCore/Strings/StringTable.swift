import Foundation

public enum LabelStyle: String, Sendable, Codable, CaseIterable {
    case short
    case long
}

/// The strings the app renders itself, resolved per app.md T-10:
///
/// ```
/// key ─► cached server value ─► built-in value ─► built-in English ─► the key
/// ```
///
/// The cache is the live answer; the compiled snapshot is what a first launch,
/// an offline start or a cleared cache falls back to. An empty server value
/// counts as absent so a key this server has never heard of still lands on
/// English rather than a gap.
public struct StringTable: Sendable, Equatable {
    public var language: String
    /// Cached from `GET /i18n/{lang}` for `language`.
    public var server: I18nBundle?
    /// The compiled snapshot for `language`.
    public var builtIn: I18nBundle?
    /// The compiled English snapshot — the floor.
    public var english: I18nBundle

    public init(language: String, server: I18nBundle? = nil, builtIn: I18nBundle? = nil, english: I18nBundle) {
        self.language = language
        self.server = server
        self.builtIn = builtIn
        self.english = english
    }

    /// Tab names, empty states, filter UI (T-05).
    public func mobile(_ key: String) -> String {
        resolve(key) { $0.mobile }
    }

    /// Status messages: `waiting_server`, `connection_lost`, `retrying`.
    public func display(_ key: String) -> String {
        resolve(key) { $0.display }
    }

    /// The vocabulary `event_name_parts` composes against, merged per key.
    public var eventVocabulary: [String: String] {
        merged { $0.eventName }
    }

    /// The bundled label table for one style, merged per key. The server's
    /// `long` table already holds short words for the narrow columns (T-09).
    public func labels(_ style: LabelStyle) -> [String: String] {
        merged { $0.labels[style.rawValue] ?? [:] }
    }

    private func resolve(_ key: String, _ section: (I18nBundle) -> [String: String]) -> String {
        for bundle in [server, builtIn, english].compactMap({ $0 }) {
            if let v = section(bundle)[key], !v.isEmpty { return v }
        }
        return key
    }

    private func merged(_ section: (I18nBundle) -> [String: String]) -> [String: String] {
        var out = section(english)
        if let b = builtIn { out.merge(section(b).filter { !$0.value.isEmpty }) { _, new in new } }
        if let s = server { out.merge(section(s).filter { !$0.value.isEmpty }) { _, new in new } }
        return out
    }
}

/// Column headers and header labels are the server's words, never the app's
/// (app.md T-04).
public enum LabelResolver {
    /// `event` and `heat` are the only keys with a long form; every other header
    /// is a narrow column and renders short whatever the style says (T-09).
    public static let wideKeys: Set<String> = ["event", "heat"]

    /// The labels to render: the `style` table from `GET /i18n/{lang}` (`table`,
    /// which must be for the effective language).
    ///
    /// The style is always the device's own — the picker offers short and long
    /// and nothing else — so the operator's `settings.label_style` no longer
    /// selects between them. `settings.labels` stays the fallback for the two
    /// cases where the i18n table cannot answer: no table cached yet, or a
    /// language whose table came back empty.
    public static func labels(settings: MeetSettings, language: String?, style: LabelStyle,
                              table: StringTable?) -> [String: String] {
        guard let table else { return settings.labels }
        let out = table.labels(style)
        return out.isEmpty ? settings.labels : out
    }
}
