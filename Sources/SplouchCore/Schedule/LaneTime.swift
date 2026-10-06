import Foundation

/// What a Schedule lane's time cell shows (app.md S-22, S-23): the best time
/// known — official result or its status, else the console's, else the seed —
/// or, while an official heat is showing its gaps, the gap to the seed.
public struct LaneTime: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case seed
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

    public init(text: String, kind: Kind, spokenKey: String, speaksText: Bool = true) {
        self.text = text
        self.kind = kind
        self.spokenKey = spokenKey
        self.speaksText = speaksText
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

    public static func of(_ lane: ScheduleLane, diff: Bool = false) -> LaneTime? {
        let status = lane.resultStatus
        if diff {
            if !status.isEmpty {
                if !lane.consoleTime.isEmpty {
                    return LaneTime(text: display(lane.consoleTime), kind: .console, spokenKey: "time_console")
                }
            } else if let d = lane.resultDeltaSeconds {
                return LaneTime(
                    text: DeltaFormat.text(d), kind: lane.resultDeltaBetter == true ? .better : .worse,
                    spokenKey: "seed_diff")
            } else {
                let seed = lane.seedTime.isEmpty ? "NT" : display(lane.seedTime)
                return LaneTime(text: seed, kind: .seed, spokenKey: "time_seed")
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
        if !lane.seedTime.isEmpty {
            return LaneTime(text: display(lane.seedTime), kind: .seed, spokenKey: "time_seed")
        }
        return nil
    }
}

extension Schedule {
    /// A finished heat's console times, from the `results_snapshot` that
    /// announced it (S-22): patched in place rather than re-fetching every heat.
    /// A lane's `channel` is its lane number.
    public mutating func applyConsoleTimes(_ snap: ResultsSnapshot) {
        guard let i = heats.firstIndex(where: { $0.event == snap.event && $0.heat == snap.heat }) else { return }
        for r in snap.lanes {
            let t = LaneTime.wire(r.time)
            guard !t.isEmpty, let j = heats[i].lanes.firstIndex(where: { $0.lane == r.channel }) else { continue }
            heats[i].lanes[j].consoleTime = t
        }
    }
}
