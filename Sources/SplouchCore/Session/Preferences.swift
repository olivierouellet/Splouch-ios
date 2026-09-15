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
    /// T-09: the device's style, long until the user picks short. There is no
    /// "follow the meet" state — see the note on `LabelResolver.labels`.
    public var labelStyle: LabelStyle

    /// T-09's short/long control is withdrawn from the UI, so every meet renders
    /// the long labels whatever is stored.
    ///
    /// The stored value is read through this rather than overwritten, so a user
    /// who had chosen `short` keeps that choice and gets it back if the control
    /// returns. To revert: offer the picker again (PickerScreen.toolbar) and
    /// return `labelStyle` here.
    public var effectiveLabelStyle: LabelStyle { .long }
    /// P-11: nil is the default cloud.
    public var server: ServerAddress?
    public var savedServers: [SavedServer]

    public init(language: String? = nil, labelStyle: LabelStyle = .long, server: ServerAddress? = nil,
                savedServers: [SavedServer] = []) {
        self.language = language
        self.labelStyle = labelStyle
        self.server = server
        self.savedServers = savedServers
    }

    /// Preferences stored before the style became a two-way choice carry either
    /// no `labelStyle` or a null one, both meaning "follow the meet". They land
    /// on the new default rather than failing to decode and dropping the
    /// server list with them.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        language = try c.decodeIfPresent(String.self, forKey: .language)
        labelStyle = try c.decodeIfPresent(LabelStyle.self, forKey: .labelStyle) ?? .long
        server = try c.decodeIfPresent(ServerAddress.self, forKey: .server)
        savedServers = try c.decodeIfPresent([SavedServer].self, forKey: .savedServers) ?? []
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
