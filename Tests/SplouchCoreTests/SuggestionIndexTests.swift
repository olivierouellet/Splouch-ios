import Foundation
import Testing
@testable import SplouchCore

@Suite struct FoldTests {
    /// Every row confirmed against the reference implementation.
    @Test(arguments: [
        ("Île-des-Sœurs", "ile-des-soeurs"),
        ("soeurs", "soeurs"),
        ("Sørensen", "sorensen"),
        ("sorensen", "sorensen"),
        ("Ǿyvind", "oyvind"),
        ("José García", "jose garcia"),
        ("ELISE", "elise"),
        ("Élise", "elise"),
        ("élise", "elise"),
        ("Straße", "strasse"),
        ("Ævar", "aevar"),
        ("Þór", "thor"),
        ("Ðorđe", "dorde"),
        ("Łukasz", "lukasz"),
        ("Müller", "muller"),
        ("北島", ""),
    ])
    func foldVectors(input: String, expected: String) {
        #expect(SuggestionIndex.fold(input) == expected)
    }

    /// The property that matters more than any single output: an accented
    /// spelling and its plain spelling land on the same string.
    @Test(arguments: [
        ("Élise", "elise"), ("Sørensen", "sorensen"), ("Île-des-Sœurs", "ile-des-soeurs"),
        ("José García", "Jose Garcia"), ("Ǿyvind", "oyvind"), ("Müller", "Muller"),
        ("Þór", "thor"), ("Ðorđe", "Dorde"), ("Łukasz", "Lukasz"), ("Straße", "strasse"),
    ])
    func accentedAndPlainSpellingsAgree(accented: String, plain: String) {
        #expect(SuggestionIndex.fold(accented) == SuggestionIndex.fold(plain))
    }

    /// Step 3 is the one people skip: NFD leaves these 17 whole, so an ASCII
    /// sweep alone would delete the letter and punch a hole in the word.
    @Test func everyExpansionSurvivesTheASCIISweep() {
        #expect(SuggestionIndex.expansions.count == 17)
        for (scalar, expansion) in SuggestionIndex.expansions {
            #expect(SuggestionIndex.fold(String(Character(scalar))) == expansion)
        }
    }

    /// Not `Characters`: after decomposition `é` is one grapheme cluster whose
    /// `isASCII` is false, and `Élise` would fold to `lise`.
    @Test func leadingAccentedLetterIsKeptNotDropped() {
        #expect(SuggestionIndex.fold("Élise").hasPrefix("e"))
    }
}

@Suite struct SuggestionIndexTests {
    func lane(_ n: Int, _ name: String, club: String, swimmers: [String] = []) -> ScheduleLane {
        ScheduleLane(lane: n, name: name, club: club, seedTime: "",
                     swimmers: swimmers.map { ScheduleSwimmer(name: $0, first: String($0.split(separator: " ").last ?? "")) })
    }

    func heat(_ event: String, _ lanes: [ScheduleLane]) -> ScheduleHeat {
        ScheduleHeat(event: event, heat: "1", eventName: "", eventNameParts: nil, time: "", lanes: lanes)
    }

    var heats: [ScheduleHeat] {
        [
            heat("1", [lane(1, "Doe, Jane", club: "CAMO"), lane(2, "Sørensen, Eva", club: "Île-des-Sœurs")]),
            heat("2", [lane(4, "CAMO A", club: "CAMO", swimmers: ["Doe Jane", "Foo Bar"])]),
        ]
    }

    var index: SuggestionIndex { SuggestionIndex(heats: heats) }

    @Test func relayIsFoundByItsTeamName() {
        // A spectator may know the team and not one swimmer on it.
        let hits = index.search("camo a")
        #expect(hits.contains { $0.kind == .swimmer && $0.name == "CAMO A" })
    }

    @Test func relayIsFoundByAMemberName() {
        let hits = index.search("foo")
        #expect(hits.map(\.name) == ["Foo Bar"])
        #expect(hits[0].kind == .swimmer)
        #expect(hits[0].club == "CAMO")   // the member carries its lane's club
    }

    @Test func clubIsIndexedOnceAndFoundAccentInsensitively() {
        let hits = index.search("ile-des-soeurs")
        #expect(hits.map(\.name) == ["Île-des-Sœurs"])
        #expect(hits[0].kind == .club)
        #expect(SuggestionIndex(heats: heats + heats).search("camo").filter { $0.kind == .club }.count == 1)
    }

    @Test func searchIsCaseAndAccentInsensitiveBothWays() {
        #expect(index.search("SØRENSEN").map(\.name) == ["Sørensen, Eva"])
        #expect(index.search("sorensen").map(\.name) == ["Sørensen, Eva"])
        #expect(index.search("Sœurs").map(\.name) == ["Île-des-Sœurs"])
    }

    @Test func matchIsSubstringNotPrefix() {
        #expect(index.search("jane").map(\.name) == ["Doe Jane", "Doe, Jane"])
    }

    @Test func swimmersComeBeforeClubs() {
        let h = [heat("1", [lane(1, "CAMO, Ida", club: "CAMO")])]
        let hits = SuggestionIndex(heats: h).search("camo")
        #expect(hits.map(\.kind) == [.swimmer, .club])
    }

    @Test func emptyOrWhitespaceQueryOffersNothing() {
        #expect(index.search("").isEmpty)
        #expect(index.search("   ").isEmpty)
        // A query with no ASCII folds away; the known limit app.md records.
        #expect(index.search("北島").isEmpty)
    }

    @Test func laterLaneWinsAClubDisagreement() {
        let h = [
            heat("1", [lane(1, "Doe, Jane", club: "CAMO")]),
            heat("2", [lane(1, "Doe, Jane", club: "PCSC")]),
        ]
        let hits = SuggestionIndex(heats: h).search("doe")
        #expect(hits.map(\.club) == ["PCSC"])
    }

    @Test func resultsAreCappedAtTwenty() {
        let lanes = (1...30).map { lane($0, "Swimmer \($0)", club: "C\($0)") }
        #expect(SuggestionIndex(heats: [heat("1", lanes)]).search("s").count == 20)
    }

    @Test func blankNamesAndClubsAreNotIndexed() {
        let hits = SuggestionIndex(heats: [heat("1", [lane(1, "", club: "")])])
        #expect(hits.isEmpty)
    }

    @Test func suggestionCarriesTheChipItAdds() {
        let s = index.search("foo")[0]
        #expect(s.term == FilterTerm(kind: .swimmer, name: "Foo Bar"))
        // S-14: the chip still matches the relay lane, through its members.
        #expect(ScheduleView.laneMatches(heats[1].lanes[0], [s.term]))
    }
}
