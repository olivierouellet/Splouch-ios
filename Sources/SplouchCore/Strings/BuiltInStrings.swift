import Foundation

/// The compiled snapshot of `GET /i18n/{lang}` (app.md T-10): one checked-in
/// JSON file per language the default cloud lists, captured verbatim by
/// `scripts/update-strings.sh` and never edited by hand. It is the floor a first
/// launch, an offline start or a cleared cache draws from, and it has the same
/// shape as the file the app caches at run time, so there is one decoder.
public enum BuiltInStrings {
    static let directory = "i18n"

    /// The languages the snapshot carries.
    public static var languages: [String] {
        let urls = Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: directory) ?? []
        return urls.map { $0.deletingPathExtension().lastPathComponent }.filter { $0 != "locales" }.sorted()
    }

    /// `GET /locales` as captured — the language menu's floor when the server
    /// cannot be reached (app.md T-08). Empty only if the snapshot is missing.
    public static var locales: [LocaleEntry] {
        guard let url = Bundle.module.url(forResource: "locales", withExtension: "json", subdirectory: directory),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([LocaleEntry].self, from: data) else { return [] }
        return list
    }

    public static func body(for lang: String) -> Data? {
        guard let url = Bundle.module.url(forResource: lang, withExtension: "json", subdirectory: directory) else { return nil }
        return try? Data(contentsOf: url)
    }

    public static func bundle(for lang: String) -> I18nBundle? {
        body(for: lang).flatMap { try? I18nBundle(data: $0) }
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
