import Foundation

/// The anonymous attendance id sent with `join_meet` (app.md C-10).
///
/// Binding rules: a fresh random UUID **per server**, generated once and stored
/// locally, never derived from the device (no `identifierForVendor`, no
/// advertising id) and never shared between servers. Used server-side only for
/// `COUNT(DISTINCT)`.
public protocol VidStore: Sendable {
    /// The id for `origin` (`ServerAddress.origin`), created on first use.
    func vid(for origin: String) -> String
}

public struct InMemoryVidStore: VidStore {
    private let box = Box()

    private final class Box: @unchecked Sendable {
        let lock = NSLock()
        var ids: [String: String] = [:]
    }

    public init() {}

    public func vid(for origin: String) -> String {
        box.lock.lock()
        defer { box.lock.unlock() }
        if let v = box.ids[origin] { return v }
        let v = UUID().uuidString.lowercased()
        box.ids[origin] = v
        return v
    }
}

public struct UserDefaultsVidStore: VidStore {
    private let box: Box
    private static let prefix = "splouch.vid."

    /// `UserDefaults` is documented thread-safe but not marked Sendable in this SDK.
    private final class Box: @unchecked Sendable {
        let defaults: UserDefaults
        init(_ d: UserDefaults) { defaults = d }
    }

    public init(defaults: UserDefaults = .standard) {
        self.box = Box(defaults)
    }

    public func vid(for origin: String) -> String {
        let key = Self.prefix + origin
        if let v = box.defaults.string(forKey: key), !v.isEmpty { return v }
        let v = UUID().uuidString.lowercased()
        box.defaults.set(v, forKey: key)
        return v
    }
}
