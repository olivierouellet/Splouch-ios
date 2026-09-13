import Foundation
import Testing
@testable import SplouchCore

/// Every server-owned word the app asks for must exist in the captured snapshot
/// (app.md T-05, T-10). This is what stops the app drifting ahead of the server:
/// a key used here that `GET /i18n/en` → `mobile` does not carry would render as
/// its own name on every phone until the server learns it.
@Suite struct SnapshotCoverageTests {
    static var sourcesRoot: URL {
        // Tests/SplouchCoreTests/<file> → repo root → Sources
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources")
    }

    /// Keys reached through `MeetTab.key` rather than a literal at the call site.
    static let indirectKeys = ["scoreboard", "results", "schedule"]

    static func mobileKeysUsedInSources() throws -> [String: [String]] {
        let fm = FileManager.default
        var found: [String: [String]] = [:]
        guard let e = fm.enumerator(at: sourcesRoot, includingPropertiesForKeys: nil) else { return found }
        let call = try NSRegularExpression(pattern: #"\.mobile\(([^()]*(?:\([^()]*\)[^()]*)*)\)"#)
        let literal = try NSRegularExpression(pattern: #""([a-z_]+)""#)
        for case let url as URL in e where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            let ns = text as NSString
            for m in call.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let args = ns.substring(with: m.range(at: 1))
                for l in literal.matches(in: args, range: NSRange(location: 0, length: (args as NSString).length)) {
                    let key = (args as NSString).substring(with: l.range(at: 1))
                    found[key, default: []].append(url.lastPathComponent)
                }
            }
        }
        for k in indirectKeys { found[k, default: []].append("MeetShell.swift (MeetTab.key)") }
        return found
    }

    @Test func everyMobileKeyTheAppUsesIsInTheSnapshot() throws {
        let used = try Self.mobileKeysUsedInSources()
        #expect(used.count >= 20, "the scan found too few call sites to be trusted")
        let served = BuiltInStrings.english.mobile
        let missing = used.filter { served[$0.key] == nil }.sorted { $0.key < $1.key }
        #expect(missing.isEmpty, "keys used but not served: \(missing.map { "\($0.key) in \($0.value.joined(separator: ", "))" })")
    }
}
