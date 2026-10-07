import Foundation
import Testing

@testable import SplouchCore

/// P-01, P-21: states and provinces named in full from the bundled table.
@Suite struct SubdivisionsTests {
    @Test(arguments: [
        ("CA", "QC", "Québec"),
        ("CA", "quebec", "Québec"),  // folded
        ("CA", "PQ", "Québec"),  // an alias
        ("ca", "on", "Ontario"),
        ("US", "NY", "New York"),
        ("MX", "CDMX", "Ciudad de México"),
        ("MX", "NL", "Nuevo León"),
    ])
    func knownSpellingsAreNamedInFull(country: String, province: String, name: String) {
        #expect(Subdivisions.name(country: country, province: province) == name)
    }

    /// The code means nothing without its country: `CA` is California only in the US.
    @Test func aProvinceIsLookedUpInItsOwnCountry() {
        #expect(Subdivisions.lookup(country: "US", province: "QC") == nil)
        #expect(Subdivisions.name(country: "", province: "QC") == "QC")
        #expect(Subdivisions.name(country: "US", province: "CA") == "California")
    }

    @Test func anUnknownProvinceIsShownAsSent() {
        #expect(Subdivisions.name(country: "DE", province: "Bayern") == "Bayern")
        #expect(Subdivisions.name(country: "CA", province: "") == "")
    }

    /// Canada has two official languages, so its provinces are named in the
    /// reader's: French where it differs, English otherwise. Québec keeps its
    /// accent in both; the US and Mexico are never translated.
    @Test(arguments: [
        ("CA", "BC", "fr", "Colombie-Britannique"),
        ("CA", "BC", "en", "British Columbia"),
        ("CA", "BC", "es", "British Columbia"),
        ("CA", "Colombie-Britannique", "en", "British Columbia"),
        ("CA", "PEI", "fr", "Île-du-Prince-Édouard"),
        ("CA", "ON", "fr", "Ontario"),
        ("CA", "QC", "en", "Québec"),
        ("CA", "QC", "fr", "Québec"),
        ("US", "NY", "fr", "New York"),
        ("MX", "CMX", "en", "Ciudad de México"),
    ])
    func aProvinceIsNamedInTheReadersLanguage(country: String, province: String, lang: String, name: String) {
        #expect(Subdivisions.name(country: country, province: province, locale: Locale(identifier: lang)) == name)
    }

    @Test func aMeetIsFoundByItsProvincesFullName() {
        let m = MeetSummary(
            id: "m", name: "Invitational", location: "", sport: "", organizer: "", meetDate: "",
            offline: false, hasPickerImage: false, country: "CA", province: "QC")
        #expect(MeetSearch.filter([m], query: "québec").count == 1)
        #expect(m.region(locale: Locale(identifier: "en")) == "Québec, Canada")
        let bc = MeetSummary(
            id: "b", name: "Invitational", location: "", sport: "", organizer: "", meetDate: "",
            offline: false, hasPickerImage: false, country: "CA", province: "BC")
        #expect(bc.region(locale: Locale(identifier: "fr")) == "Colombie-Britannique, Canada")
        #expect(MeetSearch.filter([bc], query: "colombie", locale: Locale(identifier: "fr")).count == 1)
        #expect(
            MeetFilter.Province(country: "CA", name: "BC").label(locale: Locale(identifier: "fr"))
                == "Colombie-Britannique, Canada")
    }
}
