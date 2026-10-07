import Foundation
import Testing

@testable import SplouchCore

/// P-21: the picker's filter by country, state/province and club, remembered.
@Suite struct MeetFilterTests {
    func meet(_ id: String, country: String = "", province: String = "", organizer: String = "") -> MeetSummary {
        MeetSummary(
            id: id, name: id, location: "", sport: "", organizer: organizer, meetDate: "",
            offline: false, hasPickerImage: false, country: country, province: province)
    }

    var meets: [MeetSummary] {
        [
            meet("mtl", country: "CA", province: "QC", organizer: "CAMO"),
            meet("qc", country: "CA", province: "QC", organizer: "Rouge et Or"),
            meet("tor", country: "CA", province: "ON", organizer: "Etobicoke"),
            meet("nyc", country: "US", province: "NY", organizer: "Asphalt Green"),
            meet("bare"),
        ]
    }

    let en = Locale(identifier: "en")

    @Test func anEmptyFilterLeavesEveryMeetInOrder() {
        #expect(!MeetFilter().isActive)
        #expect(MeetFilter().apply(meets).map(\.id) == ["mtl", "qc", "tor", "nyc", "bare"])
    }

    @Test func valuesOfOneFacetAreAlternatives() {
        let f = MeetFilter(clubs: ["CAMO", "Etobicoke"])
        #expect(f.apply(meets).map(\.id) == ["mtl", "tor"])
    }

    /// A country, a province and a club: a meet holding any one of them shows.
    @Test func facetsAreAlternativesToo() {
        let f = MeetFilter(countries: ["US"], provinces: [.init(country: "CA", name: "ON")], clubs: ["CAMO"])
        #expect(f.apply(meets).map(\.id) == ["mtl", "tor", "nyc"])
    }

    /// A meet that recorded no country is not "in" any country.
    @Test func anEmptyFieldFailsAnActiveFacet() {
        #expect(!MeetFilter(countries: ["CA"]).matches(meet("bare")))
        #expect(!MeetFilter(provinces: [.init(country: "", name: "")]).matches(meet("bare")))
        #expect(!MeetFilter(clubs: [""]).matches(meet("bare")))
    }

    @Test func clubsAndProvincesAreComparedFolded() {
        #expect(MeetFilter(clubs: ["rouge ET or"]).matches(meets[1]))
        #expect(MeetFilter(provinces: [.init(country: "ca", name: "qc")]).matches(meets[0]))
        #expect(MeetFilter(countries: ["CA"]).matches(meet("x", country: "ca")))
    }

    /// `QC` in Canada is not a `QC` somewhere else.
    @Test func aProvinceIsOnlyOneWithItsCountry() {
        #expect(!MeetFilter(provinces: [.init(country: "US", name: "QC")]).matches(meets[0]))
    }

    @Test func togglingAClubTwiceLeavesNoFilter() {
        var f = MeetFilter()
        f.toggle(club: "CAMO")
        #expect(f.has(club: "camo"))
        f.toggle(club: "camo")
        #expect(!f.isActive)
    }

    /// Provinces are choices of their own: dropping their country keeps them.
    @Test func droppingACountryKeepsItsProvinces() {
        var f = MeetFilter(countries: ["CA"], provinces: [.init(country: "CA", name: "QC")])
        f.toggle(country: "CA")
        #expect(f.countries.isEmpty)
        #expect(f.provinces == [.init(country: "CA", name: "QC")])
    }

    /// Typed letters kept upper-cased, without spaces or symbols.
    @Test func aTypedClubIsKeptAsItsOfficialLetters() {
        #expect(MeetFilter.clubLetters("  c.a.m.o ") == "CAMO")
        #expect(MeetFilter.clubLetters("Rouge-et-Or!") == "ROUGEETOR")
        var f = MeetFilter()
        f.add(clubLetters: " camo ")
        #expect(f.clubs == ["CAMO"])
        f.add(clubLetters: "C A M O")
        f.add(clubLetters: " .- ")
        #expect(f.clubs == ["CAMO"])
        #expect(f.apply(meets).map(\.id) == ["mtl"])
    }

    /// `C.A.M.O.` on the meet is the `CAMO` chosen.
    @Test func clubsMatchByLettersAndDigitsOnly() {
        #expect(MeetFilter(clubs: ["CAMO"]).matches(meet("x", organizer: "C.A.M.O.")))
        #expect(!MeetFilter(clubs: ["CAMO"]).matches(meet("x", organizer: "CAMOX")))
    }

    /// Clubs from the list; every country and province the app knows, whether
    /// or not a meet of the list is there.
    @Test func optionsOfferEveryKnownRegionSortedAsRead() {
        let o = MeetFilter().options(for: meets, locale: en)
        #expect(o.countries == ["CA", "MX", "US"])
        #expect(o.provinces.count == 13 + 32 + 56)
        #expect(o.provinces.first?.label(locale: en) == "Aguascalientes, Mexico")
        #expect(o.clubs == ["Asphalt Green", "CAMO", "Etobicoke", "Rouge et Or"])
    }

    /// Any province may widen what a country lets through, so all stay offered.
    @Test func provincesStayOfferedWhateverTheCountries() {
        let o = MeetFilter(countries: ["CA"]).options(for: meets, locale: en)
        #expect(o.provinces.count == 13 + 32 + 56)
    }

    /// A region the app does not know is offered once the list holds it.
    @Test func anUnknownRegionTheListHoldsIsOffered() {
        let o = MeetFilter().options(for: [meet("muc", country: "DE", province: "BY")], locale: en)
        #expect(o.countries.contains("DE"))
        #expect(o.provinces.contains(.init(country: "DE", name: "BY")))
    }

    /// A chosen club gone from today's list can still be unchecked.
    @Test func aChosenValueTheListNoLongerHoldsIsStillOffered() {
        let o = MeetFilter(countries: ["FR"], clubs: ["Gone"]).options(for: meets, locale: en)
        #expect(o.countries.contains("FR"))
        #expect(o.clubs.contains("Gone"))
    }

    @Test func aProvinceIsNamedInFullWithItsCountry() {
        #expect(MeetFilter.Province(country: "CA", name: "QC").label(locale: en) == "Québec, Canada")
        #expect(MeetFilter.Province(country: "DE", name: "BY").label(locale: en) == "BY, Germany")
    }

    /// `QC`, `Québec` and `quebec` are one province, so one choice.
    @Test func spellingsOfOneKnownProvinceAreOneChoice() {
        let spelled = [
            meet("a", country: "CA", province: "QC"), meet("b", country: "CA", province: "Québec"),
            meet("c", country: "CA", province: "quebec"),
        ]
        let quebec = MeetFilter().options(for: spelled, locale: en).provinces.filter {
            $0.label(locale: en) == "Québec, Canada"
        }
        #expect(quebec.count == 1)
        #expect(MeetFilter(provinces: [quebec[0]]).apply(spelled).count == 3)
    }

    // MARK: - Remembered

    @Test func theFilterSurvivesAnEncodeAndDecode() throws {
        var p = Preferences()
        p.meetFilter = MeetFilter(countries: ["CA"], provinces: [.init(country: "CA", name: "QC")], clubs: ["CAMO"])
        let back = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(p))
        #expect(back.meetFilter == p.meetFilter)
    }

    /// Stored before P-21: no key, no filter, and nothing else lost.
    @Test func preferencesWithoutAFilterDecodeToNone() throws {
        let json = #"{"introSeen":true,"savedServers":[]}"#
        let p = try JSONDecoder().decode(Preferences.self, from: Data(json.utf8))
        #expect(p.introSeen)
        #expect(!p.meetFilter.isActive)
    }

    @Test func aFilterThatNoLongerDecodesCostsOnlyTheFilter() throws {
        let json = #"{"introSeen":true,"meetFilter":{"countries":3}}"#
        let p = try JSONDecoder().decode(Preferences.self, from: Data(json.utf8))
        #expect(p.introSeen)
        #expect(!p.meetFilter.isActive)
    }

    @MainActor @Test func theModelStoresTheFilterAtOnce() {
        let store = InMemoryPreferencesStore()
        let app = AppModel(
            defaultServer: ServerAddress(base: "https://splouch.org")!, preferencesStore: store)
        app.setMeetFilter(MeetFilter(clubs: ["CAMO"]))
        #expect(store.load().meetFilter.clubs == ["CAMO"])
    }
}
