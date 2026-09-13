import Foundation

/// A server the user added by hand (app.md P-13). What they typed is kept; a
/// server absent from every directory still works.
public struct SavedServer: Sendable, Codable, Equatable, Identifiable {
    public var name: String
    public var address: ServerAddress
    public var id: String { address.origin }

    public init(name: String, address: ServerAddress) {
        self.name = name
        self.address = address
    }
}

/// Per-device choices. Filters are deliberately not here (S-20).
public struct Preferences: Sendable, Codable, Equatable {
    /// T-08: nil follows each meet's locale (T-06).
    public var language: String?
    /// T-09: nil follows the operator's `label_style`.
    public var labelStyle: LabelStyle?
    /// P-11: nil is the default cloud.
    public var server: ServerAddress?
    public var savedServers: [SavedServer]

    public init(language: String? = nil, labelStyle: LabelStyle? = nil, server: ServerAddress? = nil,
                savedServers: [SavedServer] = []) {
        self.language = language
        self.labelStyle = labelStyle
        self.server = server
        self.savedServers = savedServers
    }
}

public protocol PreferencesStore: Sendable {
    func load() -> Preferences
    func save(_ preferences: Preferences)
}

public struct UserDefaultsPreferencesStore: PreferencesStore {
    private let box: Box
    private static let key = "splouch.preferences"

    private final class Box: @unchecked Sendable {
        let defaults: UserDefaults
        init(_ d: UserDefaults) { defaults = d }
    }

    public init(defaults: UserDefaults = .standard) {
        box = Box(defaults)
    }

    public func load() -> Preferences {
        guard let data = box.defaults.data(forKey: Self.key),
              let p = try? JSONDecoder().decode(Preferences.self, from: data) else { return Preferences() }
        return p
    }

    public func save(_ preferences: Preferences) {
        if let data = try? JSONEncoder().encode(preferences) {
            box.defaults.set(data, forKey: Self.key)
        }
    }
}

public final class InMemoryPreferencesStore: PreferencesStore, @unchecked Sendable {
    private let lock = NSLock()
    private var value: Preferences

    public init(_ initial: Preferences = Preferences()) {
        value = initial
    }

    public func load() -> Preferences { lock.withLock { value } }
    public func save(_ preferences: Preferences) { lock.withLock { value = preferences } }
}
