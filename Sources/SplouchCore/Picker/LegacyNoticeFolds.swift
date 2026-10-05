import Foundation

/// P-06 and P-07 used to fold to pills, and each fold was stored per server as
/// `splouch.fold.<notice>.<origin>` holding the words folded. Since v3, amended
/// (app.md, 2026-10-05), the disclaimer is one line nobody closes and the
/// privacy note lives in settings, so those values mean nothing. This deletes
/// them, once per install.
public enum LegacyNoticeFolds {
    static let prefix = "splouch.fold."
    static let done = "splouch.folds_purged"

    public static func purge(_ defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: done) else { return }
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
        }
        defaults.set(true, forKey: done)
    }
}
