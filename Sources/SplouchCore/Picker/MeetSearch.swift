import Foundation

/// P-17: search over the meet list P-01 already fetched. There is no search
/// endpoint — a cloud lists tens of meets, so a query is a filter over the
/// cards, answered on every keystroke with no debounce, the same reasoning as
/// S-09. Folded with S-09's own fold on both sides: a second one would let
/// `montreal` find `Montréal` on one client and not another.
public enum MeetSearch {
    /// The field appears once the list holds this many meets. Under it the
    /// picker looks as it always has, and nothing is filtered. Three, not the
    /// contract's five: a departure chosen for this app (parity.md P-17).
    public static let threshold = 3

    public static func isShown(meetCount: Int) -> Bool { meetCount >= threshold }

    /// What a meet is searched on: what its card shows, plus the organizer,
    /// which the card does not show — a spectator may know a meet by the club
    /// running it — and the organizer's province as sent and by its full name
    /// (`Subdivisions`), and country by code and by its name in `locale` (P-17).
    /// Empty fields are skipped rather than joined as double spaces.
    public static func text(of meet: MeetSummary, locale: Locale = .current) -> String {
        [
            meet.name, meet.meetDate, meet.location, meet.sport, meet.organizer, meet.province,
            Subdivisions.lookup(country: meet.country, province: meet.province)?.name ?? "",
            meet.country, meet.countryName(locale: locale) ?? "",
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " ")
    }

    /// Every word of the folded query is a substring of the folded text, in
    /// any order, so `quebec 2026` finds a meet whose location holds one and
    /// date the other. An empty or blank query matches everything.
    public static func matches(_ text: String, query: String) -> Bool {
        let key = SuggestionIndex.fold(text)
        return words(query).allSatisfy { key.contains($0) }
    }

    /// The meets the query leaves, in the server's order — live meets first
    /// (api.md §5.6) — which is never re-sorted here.
    public static func filter(_ meets: [MeetSummary], query: String, locale: Locale = .current) -> [MeetSummary] {
        let words = words(query)
        guard !words.isEmpty else { return meets }
        return meets.filter { meet in
            let key = SuggestionIndex.fold(text(of: meet, locale: locale))
            return words.allSatisfy { key.contains($0) }
        }
    }

    /// The folded query split on whitespace, empty words dropped. Folded before
    /// splitting, as the web picker does; the fold leaves only ASCII, so ASCII
    /// whitespace is all there is to split on.
    static func words(_ query: String) -> [String] {
        SuggestionIndex.fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
    }
}

extension MeetSummary {
    /// P-01: the organizer's country named in the reader's language — `CA` is
    /// *Canada* in English and French, *Canadá* in Spanish. nil when there is no
    /// code or the system does not know it.
    /// P-01: `Québec` for `QC`; a province the app does not know, as sent.
    public var provinceName: String { Subdivisions.name(country: country, province: province) }

    public func countryName(locale: Locale = .current) -> String? {
        guard !country.isEmpty else { return nil }
        return locale.localizedString(forRegionCode: country.uppercased())
    }

    /// P-01, P-18: `Québec, Canada` — the province in full when the app knows
    /// it (`Subdivisions`), else as sent, then the country's name, falling back
    /// to its code. nil when neither was recorded.
    public func region(locale: Locale = .current) -> String? {
        let parts = [provinceName, countryName(locale: locale) ?? country].filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}
