import Foundation

/// What a Schedule lane's time cell shows (app.md S-22, S-23): the best time
/// known — official result or its status, else the console's, else the seed —
/// or, while a heat is swapped (S-23), the gap to the seed: the official
/// result's once there is one, else the console time's.
public struct LaneTime: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case seed
        /// A seed swum in another course than the meet's (S-27), in its own colour.
        case seedOther
        case console
        case official
        /// A gap to the seed, faster (`delta_better`) or slower (`delta_worse`).
        case better
        case worse
    }

    public var text: String
    public var kind: Kind
    /// The `[mobile]` word a screen reader says for this cell, before `text`
    /// when `speaksText` — "Official time 30.12", but "Disqualified" alone.
    public var spokenKey: String
    public var speaksText: Bool
    /// What a screen reader says after `text`: a `.seedOther` seed's course
    /// (S-27), "Seed time 1:01.00 LCM", since the cell shows it only by colour.
    public var spokenSuffix: String

    public init(text: String, kind: Kind, spokenKey: String, speaksText: Bool = true, spokenSuffix: String = "") {
        self.text = text
        self.kind = kind
        self.spokenKey = spokenKey
        self.speaksText = speaksText
        self.spokenSuffix = spokenSuffix
    }

    /// Every time travels as `HH:MM:SS.hh`; the hours go when there are none.
    public static func display(_ time: String) -> String {
        time.hasPrefix("00:") && time.count > 8 ? String(time.dropFirst(3)) : time
    }

    /// A console time as `results_snapshot` carries it (`58.21`, `1:02.34`), in
    /// the wire form the schedule uses. "" when it is not a time.
    public static func wire(_ time: String) -> String {
        let parts = time.trimmingCharacters(in: .whitespaces).split(separator: ":", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count) else { return "" }
        let minutes = parts.count == 2 ? Int(parts[0]) : 0
        let sec = parts.last!.split(separator: ".", omittingEmptySubsequences: false)
        guard let minutes, sec.count == 2, sec[1].count == 2, (1...2).contains(sec[0].count),
            let s = Int(sec[0]), let c = Int(sec[1])
        else { return "" }
        let h = (minutes * 60 + s) * 100 + c
        guard h > 0 else { return "" }
        func two(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }
        return "\(two(h / 360000)):\(two(h / 6000 % 60)):\(two(h / 100 % 60)).\(two(h % 100))"
    }

    /// S-23: a heat whose times swap on a tap for their gaps to the seed — an
    /// official one, or one the console has timed.
    public static func swaps(official: Bool, lanes: [ScheduleLane]) -> Bool {
        official || lanes.contains { !$0.consoleTime.isEmpty }
    }

    /// A time in hundredths: `HH:MM:SS.hh` as the schedule carries it, or a
    /// seed as Hytek wrote it (`58.21`, `1:02.34`) — the server's own
    /// `parse_time_hundredths`. nil when empty, zero or not a time.
    public static func hundredths(_ time: String) -> Int? {
        let parts = time.trimmingCharacters(in: .whitespaces).split(separator: ":", omittingEmptySubsequences: false)
        let sec = parts.last?.split(separator: ".", omittingEmptySubsequences: false) ?? []
        let fields = parts.dropLast() + sec
        guard (1...3).contains(parts.count), sec.count == 2, sec[1].count == 2,
            parts.count == 3 ? parts[1].count == 2 && sec[0].count == 2 : (1...2).contains(sec[0].count),
            fields.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } })
        else { return nil }
        let n = fields.map { Int($0)! }.reversed().map { $0 }  // c, s, m?, h?
        let h = n.count > 3 ? n[3] : 0
        let m = n.count > 2 ? n[2] : 0
        let total = ((h * 60 + m) * 60 + n[1]) * 100 + n[0]
        return total > 0 ? total : nil
    }

    /// `console_time` − `seed_time` in hundredths, on the server's rule; nil with
    /// no console time, no seed, or a seed from another course (S-27).
    static func consoleGap(_ lane: ScheduleLane) -> Int? {
        guard lane.seedCourse.isEmpty, let c = hundredths(lane.consoleTime), let s = hundredths(lane.seedTime)
        else { return nil }
        return c - s
    }

    static func gap(_ d: Int) -> LaneTime {
        LaneTime(text: DeltaFormat.text(Double(d) / 100), kind: d < 0 ? .better : .worse, spokenKey: "seed_diff")
    }

    /// The cell for `lane`; with `diff`, its S-23 gap to the seed. `late` is the
    /// swap's second half, where a status lane, which has no official gap, turns
    /// from its console time to the console's gap.
    public static func of(_ lane: ScheduleLane, diff: Bool = false, late: Bool = false) -> LaneTime? {
        let status = lane.resultStatus
        if diff {
            if !status.isEmpty {
                if late, let d = consoleGap(lane) { return gap(d) }
                if !lane.consoleTime.isEmpty {
                    return LaneTime(text: display(lane.consoleTime), kind: .console, spokenKey: "time_console")
                }
            } else if let d = lane.resultDeltaSeconds {
                return LaneTime(
                    text: DeltaFormat.text(d), kind: lane.resultDeltaBetter == true ? .better : .worse,
                    spokenKey: "seed_diff")
            } else if lane.resultTime.isEmpty, let d = consoleGap(lane) {
                // Not official yet: the console's own gap, on the server's rule.
                return gap(d)
            } else {
                return seed(lane)
            }
        }
        if !status.isEmpty {
            return LaneTime(
                text: status, kind: .official, spokenKey: "status_\(status.lowercased())", speaksText: false)
        }
        if !lane.resultTime.isEmpty {
            return LaneTime(text: display(lane.resultTime), kind: .official, spokenKey: "time_official")
        }
        if !lane.consoleTime.isEmpty {
            return LaneTime(text: display(lane.consoleTime), kind: .console, spokenKey: "time_console")
        }
        if !lane.seedTime.isEmpty { return seed(lane) }
        return nil
    }

    /// The seed's cell: `NT` for none. One swum in another course than the
    /// meet's (S-27) is `.seedOther`, drawn in its own colour with nothing beside
    /// it; the screen reader says the course after it, the same three letters in
    /// every language.
    static func seed(_ lane: ScheduleLane) -> LaneTime {
        if lane.seedTime.isEmpty { return LaneTime(text: "NT", kind: .seed, spokenKey: "time_seed") }
        let other = !lane.seedCourse.isEmpty
        return LaneTime(
            text: display(lane.seedTime), kind: other ? .seedOther : .seed, spokenKey: "time_seed",
            spokenSuffix: lane.seedCourse)
    }
}

extension Schedule {
    /// A finished heat's console times, from the `results_snapshot` that
    /// announced it (S-22): patched in place rather than re-fetching every heat.
    /// A lane's `channel` is its lane number; the heat is matched on its round
    /// too (S-24).
    public mutating func applyConsoleTimes(_ snap: ResultsSnapshot) {
        let ref = HeatRef(event: snap.event, heat: snap.heat, round: snap.round)
        guard let i = heats.firstIndex(where: ref.matches) else { return }
        for r in snap.lanes {
            let t = LaneTime.wire(r.time)
            guard !t.isEmpty, let j = heats[i].lanes.firstIndex(where: { $0.lane == r.channel }) else { continue }
            heats[i].lanes[j].consoleTime = t
        }
    }
}
