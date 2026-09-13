import Foundation

/// The compiled snapshot of `GET /i18n/{lang}` (app.md T-10): the floor a first
/// launch, an offline start or a cleared cache draws from. Refreshed by
/// `scripts/update-strings.sh`, never edited by hand.
public enum BuiltInStrings {
    /// The languages the snapshot carries.
    public static var languages: [String] { generated.keys.sorted() }

    public static func bundle(for lang: String) -> I18nBundle? {
        guard let json = generated[lang] else { return nil }
        return try? I18nBundle(data: Data(json.utf8))
    }

    /// The English floor. The snapshot always carries it.
    public static var english: I18nBundle {
        bundle(for: "en") ?? I18nBundle(lang: "en")
    }

    /// A table for `lang` with no server cache yet.
    public static func table(for lang: String) -> StringTable {
        StringTable(language: lang, server: nil, builtIn: bundle(for: lang), english: english)
    }
}
