import Foundation
import Testing
@testable import SplouchUI

/// T-05, the native half: every word the app owns must exist in
/// `Localizable.xcstrings` in all three languages, or a spectator gets the key.
///
/// **This reads the catalogue, not the running app, and that is deliberate.**
/// `String(localized:)` cannot be asserted against here: `swift test` copies
/// `Localizable.xcstrings` into the resource bundle verbatim, without compiling
/// it, so every lookup falls back to its own key and `Native.retry` is the
/// string `"retry"`. Xcode does compile it — the built app carries
/// `en.lproj`/`fr.lproj`/`es.lproj/Localizable.strings` — so this is a gap in
/// the SwiftPM CLI, not a bug in the app. A test that asserted
/// `Native.retry == "Retry"` would fail while the app was perfectly correct,
/// which is why this one goes to the source of truth instead.
///
/// The scan mirrors `SnapshotCoverageTests` in the core suite: the call sites
/// are the list of keys, so a key added without a translation fails here rather
/// than reaching a phone.
@Suite struct NativeStringsCoverageTests {
    static var uiSources: URL {
        // Tests/SplouchUITests/<file> → repo root → Sources/SplouchUI
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/SplouchUI")
    }

    static var catalogueURL: URL {
        uiSources.appendingPathComponent("Resources/Localizable.xcstrings")
    }

    /// Every `String(localized: "…")` key in the module, from its call sites.
    static func keysUsedInSources() throws -> [String: [String]] {
        let fm = FileManager.default
        var found: [String: [String]] = [:]
        guard let e = fm.enumerator(at: uiSources, includingPropertiesForKeys: nil) else { return found }
        let call = try NSRegularExpression(pattern: #"String\(localized:\s*"([a-z0-9_]+)""#)
        for case let url as URL in e where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            let ns = text as NSString
            for m in call.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                found[ns.substring(with: m.range(at: 1)), default: []].append(url.lastPathComponent)
            }
        }
        return found
    }

    struct Catalogue {
        var sourceLanguage: String
        /// key → language → (value, state)
        var entries: [String: [String: (value: String, state: String)]]
    }

    static func catalogue() throws -> Catalogue {
        let data = try Data(contentsOf: catalogueURL)
        let root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let strings = root["strings"] as! [String: Any]
        var entries: [String: [String: (String, String)]] = [:]
        for (key, raw) in strings {
            let locs = (raw as? [String: Any])?["localizations"] as? [String: Any] ?? [:]
            var byLang: [String: (String, String)] = [:]
            for (lang, unit) in locs {
                guard let su = (unit as? [String: Any])?["stringUnit"] as? [String: Any] else { continue }
                byLang[lang] = (su["value"] as? String ?? "", su["state"] as? String ?? "")
            }
            entries[key] = byLang
        }
        return Catalogue(sourceLanguage: root["sourceLanguage"] as? String ?? "", entries: entries)
    }

    /// The languages `Info.plist`'s `CFBundleLocalizations` promises.
    static let languages = ["en", "fr", "es"]

    @Test func everyNativeKeyIsInTheCatalogue() throws {
        let used = try Self.keysUsedInSources()
        #expect(used.count >= 15, "the scan found too few call sites to be trusted")
        let catalogue = try Self.catalogue()
        let missing = used.keys.filter { catalogue.entries[$0] == nil }.sorted()
        #expect(missing.isEmpty, "keys used but not in Localizable.xcstrings: \(missing)")
    }

    @Test func everyNativeKeyIsTranslatedIntoAllThreeLanguages() throws {
        let used = try Self.keysUsedInSources()
        let catalogue = try Self.catalogue()
        #expect(catalogue.sourceLanguage == "en")

        var faults: [String] = []
        for key in used.keys.sorted() {
            guard let langs = catalogue.entries[key] else { continue }   // the test above owns this
            for lang in Self.languages {
                guard let unit = langs[lang] else {
                    faults.append("\(key): no \(lang)")
                    continue
                }
                if unit.value.trimmingCharacters(in: .whitespaces).isEmpty { faults.append("\(key): empty \(lang)") }
                if unit.state != "translated" { faults.append("\(key): \(lang) is '\(unit.state)'") }
            }
        }
        #expect(faults.isEmpty, "\(faults.count) untranslated: \(faults.prefix(10).joined(separator: "; "))")
    }

    /// The accessors themselves, which the two tests above never call. There is
    /// nothing to assert about the *value* here — under `swift test` each one
    /// returns its own key, per the note at the top — but reaching them proves
    /// `Bundle.module` resolves at all. It traps when a target's resources are
    /// misconfigured, and that would take down the first screen that reads a
    /// word rather than failing a build.
    @Test func theAccessorsResolveTheirBundleWithoutTrapping() {
        #expect(Bundle.module.url(forResource: "Localizable", withExtension: "xcstrings") != nil)
        for s in [Native.server, Native.addServer, Native.nearby, Native.retry,
                  Native.appearanceAuto, Native.laps, Native.meetGone, Native.invalidAddress] {
            #expect(!s.isEmpty)
        }
    }

    /// A key nobody asks for is dead weight in three languages. Xcode's own
    /// extraction also files the interpolated `Text("\(a), \(b)")` forms it finds
    /// as keys — `%@, %@` and friends — which are not words anybody translates
    /// and are skipped here rather than reported every run.
    @Test func theCatalogueCarriesNoStrandedWords() throws {
        let used = Set(try Self.keysUsedInSources().keys)
        let catalogue = try Self.catalogue()
        let extraction = try NSRegularExpression(pattern: #"^[a-z0-9_]+$"#)
        let stranded = catalogue.entries.keys.filter { key in
            guard used.contains(key) == false else { return false }
            let ns = key as NSString
            // Only real key-shaped entries count; format shapes are Xcode's.
            return extraction.firstMatch(in: key, range: NSRange(location: 0, length: ns.length)) != nil
        }.sorted()
        #expect(stranded.isEmpty, "in the catalogue but used nowhere: \(stranded)")
    }
}
