import Foundation

/// One active filter chip (app.md S-11): a swimmer or a club, matched by exact
/// name as the search suggestion supplied it.
public struct FilterTerm: Sendable, Hashable, Codable {
    public enum Kind: String, Sendable, Codable {
        case swimmer
        case club
    }

    public var kind: Kind
    public var name: String

    public init(kind: Kind, name: String) {
        self.kind = kind
        self.name = name
    }
}

/// The Schedule tab's client-side state (app.md §5.2). Lives only for the
/// session (S-20).
public struct ScheduleFilter: Sendable, Equatable {
    public var terms: [FilterTerm] = []
    /// S-16: keep every heat visible, still filtering the lanes inside.
    public var showAllHeats = false
    /// S-17: hide every heat listed ahead of the current one.
    public var upcomingOnly = false

    public init(terms: [FilterTerm] = [], showAllHeats: Bool = false, upcomingOnly: Bool = false) {
        self.terms = terms
        self.showAllHeats = showAllHeats
        self.upcomingOnly = upcomingOnly
    }

    public var isFiltering: Bool { !terms.isEmpty }
    /// The count badge (S-12).
    public var count: Int { terms.count }

    public func contains(_ term: FilterTerm) -> Bool { terms.contains(term) }

    /// Adds unless already present (S-10: an added suggestion is inert).
    public mutating func add(_ term: FilterTerm) {
        if !terms.contains(term) { terms.append(term) }
    }

    public mutating func remove(_ term: FilterTerm) {
        terms.removeAll { $0 == term }
    }

    /// S-18: clears filters and both toggles.
    public mutating func reset() {
        self = ScheduleFilter()
    }

    /// After a new schedule arrives (S-21): keep the filters whose names still
    /// exist in it; silently dropping them mid-meet is worse than a stale list,
    /// but a chip that can never match again is noise.
    public mutating func prune(to heats: [ScheduleHeat]) {
        var swimmers = Set<String>()
        var clubs = Set<String>()
        for h in heats {
            for l in h.lanes {
                if !l.name.isEmpty { swimmers.insert(l.name) }
                if !l.club.isEmpty { clubs.insert(l.club) }
                for s in l.swimmers where !s.name.isEmpty { swimmers.insert(s.name) }
            }
        }
        terms.removeAll { t in
            switch t.kind {
            case .swimmer: return !swimmers.contains(t.name)
            case .club: return !clubs.contains(t.name)
            }
        }
    }
}

/// The heat the meet is on, as read off the other two sockets (S-05).
public struct HeatRef: Sendable, Equatable {
    public var event: String
    public var heat: String

    public init(event: String, heat: String) {
        self.event = event.trimmingCharacters(in: .whitespaces)
        self.heat = heat.trimmingCharacters(in: .whitespaces)
    }

    public func matches(_ h: ScheduleHeat) -> Bool {
        h.event == event && h.heat == heat
    }
}

/// One card of the rendered list.
public struct VisibleHeat: Sendable, Equatable {
    public var heat: ScheduleHeat
    /// The lanes left after filtering.
    public var lanes: [ScheduleLane]
    public var isCurrent: Bool
    /// Position among visible cards, for the alternating background (S-04).
    public var stripe: Int
}

public enum ScheduleView {
    /// S-13: OR-ed. S-14: a swimmer filter matches relay members too.
    public static func laneMatches(_ lane: ScheduleLane, _ terms: [FilterTerm]) -> Bool {
        if terms.isEmpty { return true }
        for t in terms {
            switch t.kind {
            case .club:
                if lane.club == t.name { return true }
            case .swimmer:
                if lane.name == t.name { return true }
                if lane.swimmers.contains(where: { $0.name == t.name }) { return true }
            }
        }
        return false
    }

    /// The index of the current heat in the start list, or nil when unknown or
    /// not in this list — in which case Upcoming must change nothing (S-17).
    public static func currentIndex(_ heats: [ScheduleHeat], current: HeatRef?) -> Int? {
        guard let current else { return nil }
        return heats.firstIndex(where: current.matches)
    }

    /// The cards to render, in running order.
    public static func visible(_ heats: [ScheduleHeat], filter: ScheduleFilter, current: HeatRef?) -> [VisibleHeat] {
        let cut = filter.upcomingOnly ? currentIndex(heats, current: current) : nil
        var out: [VisibleHeat] = []
        for (i, h) in heats.enumerated() {
            if let cut, i < cut { continue }
            let lanes = filter.isFiltering ? h.lanes.filter { laneMatches($0, filter.terms) } : h.lanes
            if filter.isFiltering, !filter.showAllHeats, lanes.isEmpty { continue }
            out.append(VisibleHeat(heat: h, lanes: lanes, isCurrent: current?.matches(h) ?? false, stripe: out.count))
        }
        return out
    }

    /// S-03: relay members' first names joined by `·`, falling back to each
    /// member's full name, then the lane's display name, then `—`.
    public static func displayName(_ lane: ScheduleLane) -> String {
        if !lane.swimmers.isEmpty {
            let firsts = lane.swimmers.map { $0.first.isEmpty ? $0.name : $0.first }.filter { !$0.isEmpty }
            let joined = firsts.joined(separator: " \u{00B7} ")
            if !joined.isEmpty { return joined }
        }
        return lane.name.isEmpty ? "\u{2014}" : lane.name
    }
}
