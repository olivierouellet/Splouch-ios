import Foundation

/// P-06 and P-07: the picker's two served notices. Both sit above the meet list
/// and fold to a pill; neither ever goes away. Not a first-launch dialog and not
/// a consent — counting is not the reader's to refuse (C-10).
public enum PickerNotice: String, Sendable, CaseIterable {
    /// P-06, the unofficial-results disclaimer. Always shown.
    case results
    /// P-07, the attendance note. Shown only while `analytics_enabled` is true.
    case attendance

    /// The full text in `GET /picker/config` → `strings`.
    public var textKey: String {
        switch self {
        case .results: "results_disclaimer"
        case .attendance: "privacy_note"
        }
    }

    /// The pill's label.
    public var shortKey: String {
        switch self {
        case .results: "results_disclaimer_short"
        case .attendance: "privacy_note_short"
        }
    }

    /// The X's accessibility label, shared by both notices. Like `shortKey`,
    /// missing from an older server's `strings`; both then come from the
    /// strings snapshot, in the reader's language, never from the app.
    public static let collapseKey = "notice_collapse"
}

/// Which notices the reader folded, per server (app.md P-06).
///
/// Keyed on `ServerAddress.origin`, the same key `VidStore` uses, and holding
/// the **exact text** that was folded rather than a flag: a notice starts folded
/// only while the server still sends those words, so a rewording, or the same
/// notice in another language, shows in full once.
public protocol NoticeFoldStore: Sendable {
    func folded(_ notice: PickerNotice, origin: String) -> String?
    /// `nil` forgets the fold.
    func setFolded(_ text: String?, _ notice: PickerNotice, origin: String)
}

public struct InMemoryNoticeFoldStore: NoticeFoldStore {
    private let box = Box()

    private final class Box: @unchecked Sendable {
        let lock = NSLock()
        var texts: [String: String] = [:]
    }

    public init() {}

    public func folded(_ notice: PickerNotice, origin: String) -> String? {
        box.lock.withLock { box.texts[Self.key(notice, origin)] }
    }

    public func setFolded(_ text: String?, _ notice: PickerNotice, origin: String) {
        box.lock.withLock { box.texts[Self.key(notice, origin)] = text }
    }

    private static func key(_ notice: PickerNotice, _ origin: String) -> String { notice.rawValue + " " + origin }
}

public struct UserDefaultsNoticeFoldStore: NoticeFoldStore {
    private let box: Box
    private static let prefix = "splouch.fold."

    /// `UserDefaults` is documented thread-safe but not marked Sendable in this SDK.
    private final class Box: @unchecked Sendable {
        let defaults: UserDefaults
        init(_ d: UserDefaults) { defaults = d }
    }

    public init(defaults: UserDefaults = .standard) {
        self.box = Box(defaults)
    }

    public func folded(_ notice: PickerNotice, origin: String) -> String? {
        box.defaults.string(forKey: Self.key(notice, origin))
    }

    public func setFolded(_ text: String?, _ notice: PickerNotice, origin: String) {
        if let text {
            box.defaults.set(text, forKey: Self.key(notice, origin))
        } else {
            box.defaults.removeObject(forKey: Self.key(notice, origin))
        }
    }

    private static func key(_ notice: PickerNotice, _ origin: String) -> String {
        prefix + notice.rawValue + "." + origin
    }
}
