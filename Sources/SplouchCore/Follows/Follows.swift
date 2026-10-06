import Foundation
import Observation

/// One swimmer followed for heat notifications (app.md N-02): the name as the
/// start list writes it — a lane's name, a relay team, or a relay leg — and the
/// club it was found with. The server matches both after S-09's fold.
public struct FollowedSwimmer: Sendable, Codable, Hashable {
    public var name: String
    public var club: String

    public init(name: String, club: String) {
        self.name = name
        self.club = club
    }
}

/// N-02's **Upcoming**: how far ahead the notification comes.
public enum FollowLead: Sendable, Codable, Hashable {
    case minutes(Int)
    case heats(Int)

    public static let minuteChoices = [5, 10, 15]
    public static let heatChoices = [1, 2, 3]
    public static let standard = FollowLead.minutes(5)

    public var value: Int {
        switch self {
        case .minutes(let n), .heats(let n): n
        }
    }

    public var byHeats: Bool {
        if case .heats = self { return true }
        return false
    }
}

/// One meet's follows on this device (N-02), kept until the meet is gone (N-09).
public struct MeetFollows: Sendable, Codable, Equatable {
    public var swimmers: [FollowedSwimmer]
    public var lead: FollowLead
    /// N-06: also when the console reaches the heat.
    public var selected: Bool
    /// The meet's `base` (C-11) when last registered, so a new token can be
    /// sent everywhere without opening every meet again (N-07).
    public var base: String?

    public init(
        swimmers: [FollowedSwimmer] = [], lead: FollowLead = .standard, selected: Bool = true, base: String? = nil
    ) {
        self.swimmers = swimmers
        self.lead = lead
        self.selected = selected
        self.base = base
    }

    public var isEmpty: Bool { swimmers.isEmpty }

    public func contains(_ s: FollowedSwimmer) -> Bool { swimmers.contains(s) }

    /// Adds a swimmer once; a second name in another club stays a second row.
    public mutating func add(_ s: FollowedSwimmer) {
        if !swimmers.contains(s) { swimmers.append(s) }
    }

    public mutating func remove(_ s: FollowedSwimmer) {
        swimmers.removeAll { $0 == s }
    }
}

/// The device's follows, by server and meet: a meet id means something only on
/// the server whose list it came from.
public protocol FollowStore: Sendable {
    func load() -> [String: MeetFollows]
    func save(_ all: [String: MeetFollows])
}

extension FollowStore {
    public static func key(server: String, meetID: String) -> String { server + "|" + meetID }

    public func follows(server: String, meetID: String) -> MeetFollows {
        load()[Self.key(server: server, meetID: meetID)] ?? MeetFollows()
    }

    public func set(_ f: MeetFollows?, server: String, meetID: String) {
        var all = load()
        all[Self.key(server: server, meetID: meetID)] = (f?.isEmpty ?? true) ? nil : f
        save(all)
    }
}

public struct UserDefaultsFollowStore: FollowStore {
    private let box: Box
    private static let key = "splouch.follows"

    private final class Box: @unchecked Sendable {
        let defaults: UserDefaults
        init(_ d: UserDefaults) { defaults = d }
    }

    public init(defaults: UserDefaults = .standard) {
        box = Box(defaults)
    }

    public func load() -> [String: MeetFollows] {
        guard let data = box.defaults.data(forKey: Self.key),
            let all = try? JSONDecoder().decode([String: MeetFollows].self, from: data)
        else { return [:] }
        return all
    }

    public func save(_ all: [String: MeetFollows]) {
        if let data = try? JSONEncoder().encode(all) { box.defaults.set(data, forKey: Self.key) }
    }
}

public final class InMemoryFollowStore: FollowStore, @unchecked Sendable {
    private let lock = NSLock()
    private var value: [String: MeetFollows]

    public init(_ initial: [String: MeetFollows] = [:]) {
        value = initial
    }

    public func load() -> [String: MeetFollows] { lock.withLock { value } }
    public func save(_ all: [String: MeetFollows]) { lock.withLock { value = all } }
}

/// This device's push token, as APNs gave it (hex), and whether it belongs to
/// the sandbox — a debug build's (api.md §5.13).
public struct PushToken: Sendable, Equatable {
    public var hex: String
    public var sandbox: Bool

    public init(hex: String, sandbox: Bool) {
        self.hex = hex
        self.sandbox = sandbox
    }

    public init(data: Data, sandbox: Bool) {
        self.init(hex: data.map { String(format: "%02x", $0) }.joined(), sandbox: sandbox)
    }
}

/// Whether the spectator lets the app notify (N-04).
public enum PushPermission: Sendable, Equatable {
    case notAsked
    case allowed
    case refused
}

/// The `PUT /meet/{id}/follow` body (api.md §5.13). Every follow at once: no
/// add/remove protocol to fall out of step (N-07).
public struct FollowRegistration: Sendable, Equatable {
    public var token: PushToken
    public var lang: String
    public var follows: MeetFollows

    public init(token: PushToken, lang: String, follows: MeetFollows) {
        self.token = token
        self.lang = lang
        self.follows = follows
    }

    public var json: JSONValue {
        let lead: JSONValue =
            switch follows.lead {
            case .minutes(let n): .object(["minutes": .number(Double(n))])
            case .heats(let n): .object(["heats": .number(Double(n))])
            }
        return .object([
            "token": .string(token.hex),
            "platform": .string("apns"),
            "sandbox": .bool(token.sandbox),
            "lang": .string(lang),
            "swimmers": .array(
                follows.swimmers.map { .object(["name": .string($0.name), "club": .string($0.club)]) }),
            "lead": lead,
            "selected": .bool(follows.selected),
        ])
    }

    public var body: Data { (try? JSONEncoder().encode(json)) ?? Data() }
}

extension MeetFollows {
    /// N-03: a filter chip names a swimmer, not a club; the follow carries the
    /// club the start list gives that name — one follow per club when two
    /// swimmers share it.
    public static func swimmers(named name: String, in heats: [ScheduleHeat]) -> [FollowedSwimmer] {
        var clubs: [String] = []
        for h in heats {
            for l in h.lanes where l.name == name || l.swimmers.contains(where: { $0.name == name }) {
                if !clubs.contains(l.club) { clubs.append(l.club) }
            }
        }
        return clubs.map { FollowedSwimmer(name: name, club: $0) }
    }
}

/// A heat a tapped notification points at (N-08).
public struct HeatFocus: Sendable, Equatable {
    public var meetID: String
    public var event: String
    public var heat: String

    public init(meetID: String, event: String, heat: String) {
        self.meetID = meetID
        self.event = event
        self.heat = heat
    }

    /// From a notification's `userInfo`: `meet_id`, `event`, `heat` (api.md §5.13).
    public init?(userInfo: [AnyHashable: Any]) {
        guard let meet = userInfo["meet_id"] as? String, !meet.isEmpty else { return nil }
        func text(_ key: String) -> String {
            if let s = userInfo[key] as? String { return s }
            if let n = userInfo[key] as? NSNumber { return n.stringValue }
            return ""
        }
        self.init(meetID: meet, event: text("event"), heat: text("heat"))
    }
}

/// The device's side of push (N-04, N-07): the token APNs gave, whether the
/// spectator allowed notifications, and the way to ask. The UI layer fills in
/// `ask` and `token`; the core reads them, so the models stay testable without
/// UserNotifications.
@MainActor
@Observable
public final class PushCenter {
    public private(set) var token: PushToken?
    public private(set) var permission: PushPermission
    /// Asks the system (N-04) and starts APNs registration when allowed.
    public var ask: (@MainActor () async -> PushPermission)?
    /// Reads the system's answer as it stands — it can be changed in Settings
    /// at any time, and the sheet's status line must say so (N-04).
    public var current: (@MainActor () async -> PushPermission)?
    /// Called when APNs hands over a token that differs from the last one.
    public var onNewToken: (@MainActor () async -> Void)?

    public init(permission: PushPermission = .notAsked, token: PushToken? = nil) {
        self.permission = permission
        self.token = token
    }

    public var canRegister: Bool { permission == .allowed && token != nil }

    public func setPermission(_ p: PushPermission) { permission = p }

    public func setToken(_ t: PushToken) {
        guard t != token else { return }
        token = t
        if let onNewToken { Task { await onNewToken() } }
    }

    public func refresh() async {
        if let current { permission = await current() }
    }

    /// N-04: ask once, when the first swimmer is added. Already answered → as is.
    public func askIfNeeded() async -> PushPermission {
        if permission == .notAsked, let ask { permission = await ask() }
        return permission
    }
}
