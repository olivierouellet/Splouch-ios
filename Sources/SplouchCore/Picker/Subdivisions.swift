import Foundation

/// P-01, P-21: a state or province named in full. The organizer's province is
/// free text — `QC`, `Québec`, `Quebec` — and neither platform names an ISO
/// 3166-2 subdivision the way it names a country, so the app carries the names:
/// `Resources/subdivisions.json`, a verbatim copy of the server repo's
/// `shared/regions/subdivisions.json`. Each is the subdivision's own name in its
/// majority language, never translated. A province the table does not know is
/// shown as sent.
public enum Subdivisions {
    /// One subdivision: its ISO 3166-2 code, without the country, and its name.
    public struct Entry: Sendable, Equatable {
        public let code: String
        public let name: String
    }

    /// Country → every folded spelling (code, name, aliases) → its entry.
    private static let table: [String: [String: Entry]] = load()

    private struct File: Decodable {
        let countries: [String: [String: [String]]]
    }

    private static func load() -> [String: [String: Entry]] {
        guard let url = Bundle.module.url(forResource: "subdivisions", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let file = try? JSONDecoder().decode(File.self, from: data)
        else { return [:] }
        var out: [String: [String: Entry]] = [:]
        for (country, subdivisions) in file.countries {
            var spellings: [String: Entry] = [:]
            for (code, names) in subdivisions {
                guard let name = names.first else { continue }
                let entry = Entry(code: code, name: name)
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

    /// `Québec` for `QC` in Canada; anything unknown as sent.
    public static func name(country: String, province: String) -> String {
        lookup(country: country, province: province)?.name ?? province
    }
}
