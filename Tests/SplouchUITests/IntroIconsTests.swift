import Foundation
import Testing

@testable import SplouchUI

/// P-20: a page names a control and shows it, `{filter}` drawn as the filter's own
/// symbol. A token the view does not know would reach the screen as `{filtre}`, and
/// one a translation dropped would leave that language without the picture.
@Suite @MainActor struct IntroIconsTests {
    static func tokens(_ text: String) -> [String] {
        let re = try! NSRegularExpression(pattern: #"\{(\w+)\}"#)
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map {
            ns.substring(with: $0.range(at: 1))
        }
    }

    @Test func everyTokenInTheCatalogueIsAnIconTheViewDraws() throws {
        let catalogue = try NativeStringsCoverageTests.catalogue()
        var unknown: [String] = []
        for (key, langs) in catalogue.entries where key.hasPrefix("intro_") {
            for (lang, unit) in langs {
                for t in Self.tokens(unit.value) where IntroView.icons[t] == nil {
                    unknown.append("\(key) \(lang): {\(t)}")
                }
            }
        }
        #expect(unknown.isEmpty, "\(unknown)")
    }

    @Test func everyLanguageShowsTheSameIcons() throws {
        let catalogue = try NativeStringsCoverageTests.catalogue()
        var faults: [String] = []
        for (key, langs) in catalogue.entries where key.hasPrefix("intro_") {
            let en = Self.tokens(langs["en"]?.value ?? "").sorted()
            for lang in ["fr", "es"] where Self.tokens(langs[lang]?.value ?? "").sorted() != en {
                faults.append("\(key) \(lang)")
            }
        }
        #expect(faults.isEmpty, "icons differ from English: \(faults)")
        let follow = catalogue.entries["intro_follow_body"]?["en"]?.value ?? ""
        #expect(Self.tokens(follow).contains("bell"))
    }

    @Test func voiceOverReadsTheWordsAndKeepsThePlusMinus() {
        #expect(IntroView.spoken("The gear {gear} opens Settings.") == "The gear opens Settings.")
        #expect(IntroView.spoken("le filtre {filter} : seules") == "le filtre : seules")
        #expect(IntroView.spoken("Tap a heat marked {plusminus} to see") == "Tap a heat marked ± to see")
        #expect(IntroView.spoken("{unknown} stays") == "{unknown} stays")
    }
}
