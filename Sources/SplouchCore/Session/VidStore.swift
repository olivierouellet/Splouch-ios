import Foundation

/// The anonymous attendance id sent with `join_meet`, and the spectator's say
/// over it (app.md C-10).
///
/// Binding rules: a fresh random UUID **per server**, stored locally with its
/// creation date, never derived from the device (no `identifierForVendor`, no
/// advertising id) and never shared between servers. Used server-side only for
/// `COUNT(DISTINCT)`.
///
/// **Refusable, per server.** Counting is on by default; off deletes that
/// server's id and none is made until it is turned back on, when a new one is —
/// never the old. An id older than 13 months is replaced. The web's
/// `shared/static/js/count.js` keeps the same rules in `localStorage`.
public protocol VidStore: Sendable {
    /// The id for `origin` (`ServerAddress.origin`), created on first use; nil
    /// while the spectator refuses counting on that server.
    func vid(for origin: String) -> String?
    /// Whether the spectator lets `origin` count this device. True until they
    /// say otherwise.
    func counting(for origin: String) -> Bool
    /// Off forgets the id at once; on makes nothing until the next `vid(for:)`.
    func setCounting(_ on: Bool, for origin: String)
}

/// C-10's cap on an id's life. 395 days is the web's figure (`count.js`
/// `MAX_AGE`), so the two clients replace an id on the same day.
public enum VidAge {
    public static let max: TimeInterval = 395 * 24 * 3600
}

/// The rules, over whatever holds the three values. One per store, locked, so a
/// check-then-create cannot hand two sockets two ids.
private final class VidRules: @unchecked Sendable {
    private let lock = NSLock()
    private let backing: any VidBacking
    private let now: @Sendable () -> Date

    init(backing: any VidBacking, now: @escaping @Sendable () -> Date) {
        self.backing = backing
        self.now = now
    }

    func vid(for origin: String) -> String? {
        lock.withLock {
            guard !backing.refused(origin) else {
                backing.forget(origin)
                return nil
            }
            let today = now()
            if let v = backing.id(origin), !v.isEmpty {
                // An id from before ages were kept is dated now rather than
                // replaced, so nobody is counted twice the day this shipped.
                guard let born = backing.created(origin) else {
                    backing.setCreated(today, origin)
                    return v
                }
                if today.timeIntervalSince(born) <= VidAge.max { return v }
            }
            let v = UUID().uuidString.lowercased()
            backing.setID(v, origin)
            backing.setCreated(today, origin)
            return v
        }
    }

    func counting(for origin: String) -> Bool {
        lock.withLock { !backing.refused(origin) }
    }

    func setCounting(_ on: Bool, for origin: String) {
        lock.withLock {
            backing.setRefused(!on, origin)
            if !on { backing.forget(origin) }
        }
    }
}

/// Storage only; every decision is `VidRules`'.
private protocol VidBacking {
    func id(_ origin: String) -> String?
    func setID(_ id: String, _ origin: String)
    func created(_ origin: String) -> Date?
    func setCreated(_ date: Date, _ origin: String)
    func refused(_ origin: String) -> Bool
    func setRefused(_ refused: Bool, _ origin: String)
    func forget(_ origin: String)
}

public struct InMemoryVidStore: VidStore {
    private let rules: VidRules
    private let memory: Memory

    private final class Memory: VidBacking, @unchecked Sendable {
        var ids: [String: String] = [:]
        var dates: [String: Date] = [:]
        var refusals: Set<String> = []
        func id(_ o: String) -> String? { ids[o] }
        func setID(_ id: String, _ o: String) { ids[o] = id }
        func created(_ o: String) -> Date? { dates[o] }
        func setCreated(_ d: Date, _ o: String) { dates[o] = d }
        func refused(_ o: String) -> Bool { refusals.contains(o) }
        func setRefused(_ r: Bool, _ o: String) {
            if r { refusals.insert(o) } else { refusals.remove(o) }
        }
        func forget(_ o: String) {
            ids[o] = nil
            dates[o] = nil
        }
    }

    public init(now: @escaping @Sendable () -> Date = Date.init) {
        let memory = Memory()
        self.memory = memory
        self.rules = VidRules(backing: memory, now: now)
    }

    /// Test seam: an id as an older build left it, with or without a date.
    func seed(_ id: String, created: Date?, for origin: String) {
        memory.ids[origin] = id
        memory.dates[origin] = created
    }

    public func vid(for origin: String) -> String? { rules.vid(for: origin) }
    public func counting(for origin: String) -> Bool { rules.counting(for: origin) }
    public func setCounting(_ on: Bool, for origin: String) { rules.setCounting(on, for: origin) }
}

/// `splouch.vid.<origin>` is the id, as it has always been; `splouch.vid_at.<origin>`
/// its creation date (seconds since 1970); `splouch.count.<origin>` is present
/// only while the spectator refuses, so the default needs no write.
public struct UserDefaultsVidStore: VidStore {
    private let rules: VidRules

    private final class Defaults: VidBacking {
        let defaults: UserDefaults
        init(_ d: UserDefaults) { defaults = d }
        func id(_ o: String) -> String? { defaults.string(forKey: "splouch.vid." + o) }
        func setID(_ id: String, _ o: String) { defaults.set(id, forKey: "splouch.vid." + o) }
        func created(_ o: String) -> Date? {
            (defaults.object(forKey: "splouch.vid_at." + o) as? Double).map(Date.init(timeIntervalSince1970:))
        }
        func setCreated(_ d: Date, _ o: String) { defaults.set(d.timeIntervalSince1970, forKey: "splouch.vid_at." + o) }
        func refused(_ o: String) -> Bool { defaults.string(forKey: "splouch.count." + o) == "off" }
        func setRefused(_ r: Bool, _ o: String) {
            if r {
                defaults.set("off", forKey: "splouch.count." + o)
            } else {
                defaults.removeObject(forKey: "splouch.count." + o)
            }
        }
        func forget(_ o: String) {
            defaults.removeObject(forKey: "splouch.vid." + o)
            defaults.removeObject(forKey: "splouch.vid_at." + o)
        }
    }

    public init(defaults: UserDefaults = .standard, now: @escaping @Sendable () -> Date = Date.init) {
        rules = VidRules(backing: Defaults(defaults), now: now)
    }

    public func vid(for origin: String) -> String? { rules.vid(for: origin) }
    public func counting(for origin: String) -> Bool { rules.counting(for: origin) }
    public func setCounting(_ on: Bool, for origin: String) { rules.setCounting(on, for: origin) }
}
