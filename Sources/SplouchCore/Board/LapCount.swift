import Foundation

/// Which way `settings.lap_direction` counts (app.md `L-23`).
public enum LapDirection: String, Sendable, Equatable {
    /// The lengths the lane has completed — the console's own number.
    case up
    /// What is left of the race: `expected_splits` minus the count.
    case down

    /// Anything the wire does not recognise — including a server older than the
    /// field — counts up, which is the count that needs nothing but the console.
    public init(_ raw: String?) {
        self = LapDirection(rawValue: (raw ?? "").trimmingCharacters(in: .whitespaces).lowercased()) ?? .up
    }
}

/// L-23's two settings, resolved from `MeetSettings` once so the board does not
/// carry the whole config down to a cell.
public struct LapSettings: Sendable, Equatable {
    public var show: Bool
    public var direction: LapDirection

    public init(show: Bool = false, direction: LapDirection = .up) {
        self.show = show
        self.direction = direction
    }

    public init(_ s: MeetSettings) {
        self.init(show: s.showLaps, direction: LapDirection(s.lapDirection))
    }

    /// Off: the delta cell has one tenant and the column header is a `Δ` again.
    public static let off = LapSettings()
}

/// What the delta cell carries while the lap is its tenant (app.md `L-23`).
///
/// A lap is not a result, so it gets no column of its own and never borrows the
/// place column. It shares the delta's cell, and the handover is the signal: the
/// colour changes, the header does not.
public struct LapCount: Sendable, Equatable {
    /// The number as it is drawn — already counted up or down, already clamped.
    public let text: String
    /// The final stretch. The number stays; the colour moves from the header's
    /// accent to the timing colour a stopped chrono has. Not an animation: an
    /// earlier version pulsed this and it was removed on purpose.
    public let isFinal: Bool
}
