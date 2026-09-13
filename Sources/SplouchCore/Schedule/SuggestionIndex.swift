import Foundation

/// One typeahead row (app.md S-09, S-10): a swimmer or a club, the name the
/// filter chip will carry, and — for a swimmer — the club to show beside it.
public struct Suggestion: Sendable, Equatable {
    public var kind: FilterTerm.Kind
    public var name: String
    public var club: String

    public init(kind: FilterTerm.Kind, name: String, club: String) {
        self.kind = kind
        self.name = name
        self.club = club
    }

    /// The chip this row adds.
    public var term: FilterTerm { FilterTerm(kind: kind, name: name) }
}

/// S-09: typeahead over the start list this app already holds for S-01. There
/// is no request — the server answered from ITS list, so between a
/// `schedule_update` and our re-fetch it could offer a name no lane of ours
/// carried, and the chip would match nothing.
public struct SuggestionIndex: Sendable, Equatable {
    /// A row with its folded key precomputed; folding on every comparison is
    /// what would make a local index feel slower than the round-trip it replaced.
    struct Entry: Sendable, Equatable {
        var kind: FilterTerm.Kind
        var name: String
        var club: String
        var key: String
    }

    private var swimmers: [Entry] = []
    private var clubs: [Entry] = []

    public init() {}

    /// Every `lane.name` — relay team names included, since a spectator may know
    /// the team and not one swimmer on it — plus every `lane.swimmers[].name`,
    /// each carrying its lane's club; then one row per distinct club. Names are
    /// deduped, the later lane in schedule order winning a club disagreement.
    public init(heats: [ScheduleHeat]) {
        var byName: [String: Entry] = [:]
        var nameOrder: [String] = []
        var byClub: [String: Entry] = [:]
        var clubOrder: [String] = []

        func addName(_ name: String, club: String) {
            guard !name.isEmpty else { return }
            if byName[name] == nil { nameOrder.append(name) }
            byName[name] = Entry(kind: .swimmer, name: name, club: club, key: SuggestionIndex.fold(name))
        }

        for h in heats {
            for l in h.lanes {
                addName(l.name, club: l.club)
                for s in l.swimmers { addName(s.name, club: l.club) }
                guard !l.club.isEmpty else { continue }
                if byClub[l.club] == nil {
                    clubOrder.append(l.club)
                    byClub[l.club] = Entry(kind: .club, name: l.club, club: "", key: SuggestionIndex.fold(l.club))
                }
            }
        }

        swimmers = nameOrder.compactMap { byName[$0] }
        clubs = clubOrder.compactMap { byClub[$0] }
    }

    public var isEmpty: Bool { swimmers.isEmpty && clubs.isEmpty }

    /// Substring of the folded query against the folded key — nothing else.
    /// Matching swimmers first, then matching clubs, each in folded-name order
    /// (so `Ève` sorts with the E's, not after `Zoé`), capped at `limit`. An empty or whitespace-only query offers nothing rather than
    /// the whole index; so does one that folds away to nothing (`北島`), the
    /// known limit app.md records.
    public func search(_ query: String, limit: Int = 20) -> [Suggestion] {
        let needle = SuggestionIndex.fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !needle.isEmpty else { return [] }
        func hits(_ entries: [Entry]) -> [Entry] {
            entries.filter { $0.key.contains(needle) }.sorted { ($0.key, $0.name) < ($1.key, $1.name) }
        }
        let rows = hits(swimmers) + hits(clubs)
        return rows.prefix(limit).map { Suggestion(kind: $0.kind, name: $0.name, club: $0.club) }
    }

    // MARK: The fold

    /// The 17 letters with no canonical decomposition: NFD leaves them whole,
    /// so the ASCII sweep would delete the letter itself and punch a hole in
    /// the word. Expanded AFTER decomposing, which covers their accented forms
    /// for free — `ǿ` decomposes to `ø` plus an acute, and `ø` is in here.
    static let expansions: [Unicode.Scalar: String] = [
        "ß": "ss", "æ": "ae", "ð": "d", "ø": "o", "þ": "th", "đ": "d",
        "ħ": "h", "ı": "i", "ĳ": "ij", "ĸ": "k", "ŀ": "l", "ł": "l",
        "ŉ": "n", "ŋ": "n", "œ": "oe", "ŧ": "t", "ſ": "s",
    ]

    /// lowercase → NFD decompose → expand the table → drop every codepoint
    /// above U+007F. Applied to BOTH the query and every indexed name; that
    /// symmetry is what makes the search case- and accent-insensitive.
    ///
    /// Iterates `unicodeScalars`, not `Characters`: after decomposition `e`
    /// plus a combining acute is one grapheme cluster whose `isASCII` is false,
    /// and `Élise` would fold to `lise`.
    public static func fold(_ s: String) -> String {
        var out = ""
        for u in s.lowercased().decomposedStringWithCanonicalMapping.unicodeScalars {
            if let e = expansions[u] {
                out += e
            } else if u.isASCII {
                out.unicodeScalars.append(u)
            }
        }
        return out
    }
}
