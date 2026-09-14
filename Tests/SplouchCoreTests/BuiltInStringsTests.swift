import Testing
@testable import SplouchCore

@Suite struct BuiltInStringsTests {
    @Test func snapshotCarriesEnglishAndDecodes() {
        #expect(BuiltInStrings.languages.contains("en"))
        let en = BuiltInStrings.english
        #expect(en.lang == "en")
        #expect(en.mobile["scoreboard"] == "Scoreboard")
        #expect(en.mobile["waiting_results"]?.isEmpty == false)
        #expect(en.labels["short"]?["event"] == "EV")
        #expect(en.labels["long"]?["event"] == "EVENT")
        #expect(en.labels["long"]?["lane"] == en.labels["short"]?["lane"])
        #expect(en.eventName["unit"] == "m")
    }

    @Test func everyBundledLanguageDecodesAndIsEnglishMerged() {
        for lang in BuiltInStrings.languages {
            let b = BuiltInStrings.bundle(for: lang)
            #expect(b?.lang == lang, "\(lang)")
            #expect(b?.mobile["scoreboard"]?.isEmpty == false, "\(lang)")
        }
    }

    @Test func capturedLocalesAreTheLanguageMenusFloor() {
        let locales = BuiltInStrings.locales
        #expect(locales.map(\.code).contains("en"))
        #expect(locales.allSatisfy { !$0.name.isEmpty })
        // Every listed language has its snapshot, and vice versa.
        #expect(Set(locales.map(\.code)) == Set(BuiltInStrings.languages))
    }

    @Test func snapshotCarriesThePickerAndFilterWords() {
        let en = BuiltInStrings.english.mobile
        for k in ["page_title", "no_meets", "unnamed_meet", "results_disclaimer", "privacy_note", "offline",
                  // `prefs_auto` is deliberately absent: the server still sends it for the
                  // web picker's "Meet default" row, which this app no longer offers.
                  "language", "language_auto", "prefs_title", "prefs_labels", "prefs_short", "prefs_long",
                  "filter", "no_filters", "no_search_results", "no_matches", "swimmer", "club"] {
            #expect(en[k]?.isEmpty == false, "\(k)")
        }
    }

    @Test func tableWithoutServerResolvesFromTheSnapshot() {
        let t = BuiltInStrings.table(for: "fr")
        #expect(t.mobile("scoreboard") == "Tableau")
        #expect(t.mobile("no_such_key") == "no_such_key")
        #expect(BuiltInStrings.table(for: "xx").mobile("scoreboard") == "Scoreboard")
    }
}
