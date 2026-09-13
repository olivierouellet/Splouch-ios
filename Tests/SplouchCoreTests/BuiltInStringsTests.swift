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

    @Test func tableWithoutServerResolvesFromTheSnapshot() {
        let t = BuiltInStrings.table(for: "fr")
        #expect(t.mobile("scoreboard") == "Tableau")
        #expect(t.mobile("no_such_key") == "no_such_key")
        #expect(BuiltInStrings.table(for: "xx").mobile("scoreboard") == "Scoreboard")
    }
}
