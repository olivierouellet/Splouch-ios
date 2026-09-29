import Foundation

/// P-17: search over the meet list P-01 already fetched. There is no search
/// endpoint — a cloud lists tens of meets, so a query is a filter over the
/// cards, answered on every keystroke with no debounce, the same reasoning as
/// S-09. Folded with S-09's own fold on both sides: a second one would let
/// `montreal` find `Montréal` on one client and not another.
public enum MeetSearch {
    /// The field appears once the list holds this many meets. Under it the
    /// picker looks as it always has, and nothing is filtered.
    public static let threshold = 5

    public static func isShown(meetCount: Int) -> Bool { meetCount >= threshold }

    /// What a meet is searched on: what its card shows, plus the organizer,
    /// which the card does not show — a spectator may know a meet by the club
    /// running it. Empty fields are skipped rather than joined as double spaces.
    public static func text(of meet: MeetSummary) -> String {
        [meet.name, meet.meetDate, meet.location, meet.sport, meet.organizer]
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
    public static func filter(_ meets: [MeetSummary], query: String) -> [MeetSummary] {
        let words = words(query)
        guard !words.isEmpty else { return meets }
        return meets.filter { meet in
            let key = SuggestionIndex.fold(text(of: meet))
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
