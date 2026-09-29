import Foundation
import Testing

@testable import SplouchCore

/// P-17: search over the meet list, on the device.
@Suite struct MeetSearchTests {
    func meet(
        _ id: String, name: String = "", date: String = "", location: String = "", sport: String = "",
        organizer: String = "", offline: Bool = false
    ) -> MeetSummary {
        MeetSummary(
            id: id, name: name, location: location, sport: sport, organizer: organizer, meetDate: date,
            offline: offline, hasPickerImage: false)
    }

    var quebec: MeetSummary {
        meet(
            "q", name: "Coupe du Québec", date: "2026-10-04", location: "Île-des-Sœurs", sport: "Swimming",
            organizer: "CAMO")
    }

    @Test func theSearchTextIsTheFieldsInOrderJoinedBySpaces() {
        #expect(MeetSearch.text(of: quebec) == "Coupe du Québec 2026-10-04 Île-des-Sœurs Swimming CAMO")
    }

    /// No double space where a field is missing.
    @Test func emptyFieldsAreSkipped() {
        #expect(MeetSearch.text(of: meet("x", name: "Invitational", organizer: "CAMO")) == "Invitational CAMO")
    }

    @Test(arguments: [
        ("quebec 2026", true),  // one word from the name, one from the date
        ("2026 coupe", true),  // any order
        ("quebec 2025", false),  // every word must match
        ("QUÉBEC", true),  // case and accent folded on the query side too
        ("soeurs", true),  // œ expands; `.diacriticInsensitive` would miss this
        ("camo", true),  // the organizer is searched though never shown
        ("", true),
        ("   ", true),
    ])
    func matching(query: String, expected: Bool) {
        let text = "Coupe du Québec 2026-10-04 Île-des-Sœurs Swimming CAMO"
        #expect(MeetSearch.matches(text, query: query) == expected)
    }

    @Test func noFieldAtFourMeetsAndAFieldAtFive() {
        #expect(!MeetSearch.isShown(meetCount: 0))
        #expect(!MeetSearch.isShown(meetCount: 4))
        #expect(MeetSearch.isShown(meetCount: 5))
        #expect(MeetSearch.isShown(meetCount: 200))
    }

    /// Live first is the server's order (api.md §5.6); the filter keeps it.
    @Test func filteringKeepsTheServersOrder() {
        let meets = [
            meet("a", name: "Zeta Open", location: "Montréal"),
            meet("b", name: "Alpha Cup", location: "Laval"),
            meet("c", name: "Mid Meet", location: "Montreal", offline: true),
            meet("d", name: "Beta Meet", location: "Montréal-Nord"),
        ]
        #expect(MeetSearch.filter(meets, query: "montreal").map(\.id) == ["a", "c", "d"])
        #expect(MeetSearch.filter(meets, query: "").map(\.id) == ["a", "b", "c", "d"])
        #expect(MeetSearch.filter(meets, query: "nothing").isEmpty)
    }
}
