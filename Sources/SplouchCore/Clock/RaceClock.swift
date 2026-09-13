import Foundation

/// The race clock for the current heat (app.md L-12).
///
/// One clock per heat, not one per lane. The server re-bases it with each
/// `running_time` frame and the device ticks it in between off a monotonic
/// clock, so a wall-clock correction mid-heat cannot move it. The clock is pure
/// state over `ContinuousClock.Instant`; the owner decides when to sample it.
///
/// What it deliberately does not do: start or reset from a `lane_running` edge,
/// ease towards a re-base, or keep ticking after a suspend. `lane_running<i>`
/// only decides whether lane *i* displays it.
public struct RaceClock: Sendable, Equatable {
    public typealias Instant = ContinuousClock.Instant

    /// The relay forwards `running_time` at most once every ~2s (api.md §5.1).
    public static let syncInterval: Duration = .seconds(2)
    /// Silence for three sync intervals means the feed died, not the throttle.
    public static let staleAfter: Duration = .seconds(6)
    /// One tenth, the last digit displayed.
    public static let tickInterval: Duration = .milliseconds(100)

    public private(set) var baseHundredths: Int?
    public private(set) var baseInstant: Instant?

    public init() {}

    /// True between a re-base and a `stop()`.
    public var isRunning: Bool { baseHundredths != nil }

    public enum Reading: Sendable, Equatable {
        /// Fresh: the device is advancing the digits.
        case ticking(String)
        /// Three sync intervals past the last re-base: frozen forward, where the
        /// digits stopped, never back at the base.
        case frozen(String)

        public var text: String {
            switch self {
            case .ticking(let t), .frozen(let t): return t
            }
        }
    }

    /// Hard re-base from a `running_time` string. Returns false and changes
    /// nothing when the string is not a clock value the console could have sent.
    @discardableResult
    public mutating func rebase(_ text: String, at now: Instant) -> Bool {
        guard let h = Self.parseHundredths(text) else { return false }
        baseHundredths = h
        baseInstant = now
        return true
    }

    /// Stops the ticker and forgets the base. Leaves nothing on screen by itself:
    /// whoever stops the clock decides what replaces the digits.
    public mutating func stop() {
        baseHundredths = nil
        baseInstant = nil
    }

    public func reading(at now: Instant) -> Reading? {
        guard let base = baseHundredths, let at = baseInstant else { return nil }
        let age = now - at
        if age > Self.staleAfter {
            return .frozen(Self.formatTenths(base + Self.hundredths(in: Self.staleAfter)))
        }
        return .ticking(Self.formatTenths(base + Self.hundredths(in: max(age, .zero))))
    }

    // MARK: - Format

    /// `1:05.23`, `59.99`, `5.23` — the clock format every console sends. Anything
    /// else is not a clock and is ignored by the caller.
    public static func parseHundredths(_ text: String) -> Int? {
        let s = text.trimmingCharacters(in: .whitespaces)
        var minutes = 0
        var rest = Substring(s)
        if let colon = rest.firstIndex(of: ":") {
            let m = rest[..<colon]
            guard !m.isEmpty, m.allSatisfy(\.isASCIIDigit), let v = Int(m) else { return nil }
            minutes = v
            rest = rest[rest.index(after: colon)...]
        }
        guard let dot = rest.firstIndex(of: ".") else { return nil }
        let sec = rest[..<dot]
        let frac = rest[rest.index(after: dot)...]
        guard (1...2).contains(sec.count), sec.allSatisfy(\.isASCIIDigit),
              frac.count == 2, frac.allSatisfy(\.isASCIIDigit),
              let secs = Int(sec), let hund = Int(frac) else { return nil }
        return minutes * 6000 + secs * 100 + hund
    }

    /// Tenths, never hundredths: the value carries the relay path's latency as a
    /// near-constant offset and must not claim a precision the path lacks.
    /// Seconds are zero-padded only once there is a minutes part: `5.2`, `1:05.2`.
    public static func formatTenths(_ hundredths: Int) -> String {
        let t = max(0, hundredths) / 10
        let mm = t / 600
        let ss = (t / 10) % 60
        let d = t % 10
        if mm > 0 {
            return "\(mm):" + (ss < 10 ? "0" : "") + "\(ss).\(d)"
        }
        return "\(ss).\(d)"
    }

    static func hundredths(in duration: Duration) -> Int {
        let c = duration.components
        return Int(c.seconds) * 100 + Int(c.attoseconds / 10_000_000_000_000_000)
    }
}

private extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}
