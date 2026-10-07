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

    @Test func clubsNarrowThePlaces() {
        let f = MeetFilter(countries: ["CA"], clubs: ["CAMO", "Asphalt Green"])
        #expect(f.apply(meets).map(\.id) == ["mtl"])
    }

    /// Canada, Québec and the United States: Québec, and the whole United States.
    @Test func aProvinceNarrowsItsOwnCountryOnly() {
        let f = MeetFilter(countries: ["CA", "US"], provinces: [.init(country: "CA", name: "QC")])
        #expect(f.apply(meets).map(\.id) == ["mtl", "qc", "nyc"])
        let alone = MeetFilter(provinces: [.init(country: "CA", name: "ON")])
        #expect(alone.apply(meets).map(\.id) == ["tor"])
        let withClub = MeetFilter(
            countries: ["CA", "US"], provinces: [.init(country: "CA", name: "QC")], clubs: ["CAMO", "Asphalt Green"])
        #expect(withClub.apply(meets).map(\.id) == ["mtl", "nyc"])
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

    @Test func droppingACountryDropsItsProvinces() {
        var f = MeetFilter(
            countries: ["CA", "US"], provinces: [.init(country: "CA", name: "QC"), .init(country: "US", name: "NY")])
        f.toggle(country: "CA")
        #expect(f.countries == ["US"])
        #expect(f.provinces == [.init(country: "US", name: "NY")])
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

    @Test func provincesNarrowToTheChosenCountries() {
        let o = MeetFilter(countries: ["CA"]).options(for: meets, locale: en)
        #expect(o.provinces.count == 13)
        #expect(o.provinces.allSatisfy { $0.country == "CA" })
        #expect(o.provinces.first?.label(locale: en) == "Alberta, Canada")
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
