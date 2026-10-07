import Foundation

/// P-01, P-21: a state or province named in full. The organizer's province is
/// free text — `QC`, `Québec`, `Quebec` — and neither platform names an ISO
/// 3166-2 subdivision the way it names a country, so the app carries the names:
/// `Resources/subdivisions.json`, a verbatim copy of the server repo's
/// `shared/regions/subdivisions.json`. Each is the subdivision's own name in its
/// majority language, translated only where the country has two or more official
/// languages (`names`: Canada's in French). A province the table does not know
/// is shown as sent.
public enum Subdivisions {
    /// One subdivision: its ISO 3166-2 code, without the country, its name, and
    /// its name in each language that names it otherwise.
    public struct Entry: Sendable, Equatable {
        public let code: String
        public let name: String
        public var names: [String: String] = [:]

        /// `Colombie-Britannique` in French, `British Columbia` in any other language.
        public func name(locale: Locale) -> String {
            locale.language.languageCode.flatMap { names[$0.identifier] } ?? name
        }
    }

    /// Country → every folded spelling (code, name, aliases) → its entry.
    private static let table: [String: [String: Entry]] = load()

    private struct File: Decodable {
        let countries: [String: [String: [String]]]
        /// Country → language → code → name.
        var names: [String: [String: [String: String]]]?
    }

    private static func load() -> [String: [String: Entry]] {
        guard let url = Bundle.module.url(forResource: "subdivisions", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let file = try? JSONDecoder().decode(File.self, from: data)
        else { return [:] }
        var out: [String: [String: Entry]] = [:]
        for (country, subdivisions) in file.countries {
            var spellings: [String: Entry] = [:]
            let translated = file.names?[country] ?? [:]
            for (code, names) in subdivisions {
                guard let name = names.first else { continue }
                let entry = Entry(code: code, name: name, names: translated.compactMapValues { $0[code] })
                for s in [code] + names { spellings[SuggestionIndex.fold(s)] = entry }
            }
            out[country.uppercased()] = spellings
        }
        return out
    }

    /// The subdivision `province` spells in `country`, matched by code or any
    /// listed spelling, folded as S-09 folds; nil when the table has no such one.
    public static func lookup(country: String, province: String) -> Entry? {
        let key = SuggestionIndex.fold(province)
        guard !key.isEmpty else { return nil }
        return table[country.uppercased()]?[key]
    }

    /// `Québec` for `QC` in Canada, `Colombie-Britannique` for `BC` in French;
    /// anything unknown as sent.
    public static func name(country: String, province: String, locale: Locale = .current) -> String {
        lookup(country: country, province: province)?.name(locale: locale) ?? province
    }
}
