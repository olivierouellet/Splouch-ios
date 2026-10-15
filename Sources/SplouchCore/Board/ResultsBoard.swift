import Foundation

/// One row of the Results tab grid (app.md §4).
public struct ResultRow: Sendable, Equatable {
    /// The lane number cell: the result's `channel`, or the row's own lane in
    /// lane order, or empty for an unfilled row of a ranking — that row is no
    /// lane at all, and its still water (L-25) says so without a dash.
    public var laneLabel: String
    /// Which row this is whatever screen position it is drawn at: the lane's
    /// row (`channel - firstLane + 1`) in lane order, the rank in place order.
    /// L-26 turns the lanes around by moving rows, and this is what moves.
    public var slot: Int
    public var name = ""
    public var alt = ""
    public var club = ""
    /// `—` when there is no time (R-07).
    public var time = "\u{2014}"
    /// Empty when there is no place — no dash, no `#` (R-07).
    public var place = ""
    public var deltaSeconds: Double?
    public var deltaBetter: Bool?
    /// Final times carry the locked styling (R-09).
    public var locked = false
    public var isEmpty = true

    public init(laneLabel: String, slot: Int = 0) {
        self.laneLabel = laneLabel
        self.slot = slot
    }
}

public enum ResultsBoard {
    /// The empty grid shown until the first snapshot, and again after a wipe
    /// (R-01, R-02). Row *i* is lane `i + firstLane - 1` (L-04).
    public static func empty(numLanes: Int, firstLane: Int = 1) -> [ResultRow] {
        (1...max(1, numLanes)).map { ResultRow(laneLabel: String($0 + firstLane - 1), slot: $0) }
    }

    /// Place each result on a row, in the reader's `order` (P-23) over the
    /// pool's `sort`. Lane order — `sort == "lane"`, and when `sort` is absent —
    /// puts a result on the row of its `channel`, the pool's lane number, at row
    /// `channel - firstLane + 1`, so a lane without a final time leaves its row
    /// blank (R-05); `descending` turns those rows around (L-26). Place order
    /// fills rows top-down as a ranking (R-06), ranked here by `place_int` since
    /// the pool may have sorted by lane. A `channel` outside the board is
    /// dropped. A filled row is labelled with its `channel` — lane 0 too, in a
    /// pool numbered from 0.
    public static func rows(
        _ snapshot: ResultsSnapshot, numLanes: Int, firstLane: Int = 1,
        order: ResultsOrder = .pool, descending: Bool = false
    ) -> [ResultRow] {
        let n = max(1, numLanes)
        let laneMode = order.resolve(snapshot.sort) == .lane
        let lanes =
            laneMode
            ? snapshot.lanes
            : snapshot.lanes.sorted { (rank($0), $0.channel) < (rank($1), $1.channel) }
        var byRow: [Int: ResultLane] = [:]
        for (idx, r) in lanes.enumerated() {
            let row = laneMode ? r.channel - firstLane + 1 : idx + 1
            if (1...n).contains(row) { byRow[row] = r }
        }
        let slots = laneMode && descending ? Array((1...n).reversed()) : Array(1...n)
        return slots.map { i in
            guard let r = byRow[i] else {
                return ResultRow(laneLabel: laneMode ? String(i + firstLane - 1) : "", slot: i)
            }
            var row = ResultRow(laneLabel: String(r.channel), slot: i)
            row.name = r.name
            row.alt = r.alt
            row.club = r.club
            let time = r.time.trimmingCharacters(in: .whitespaces)
            row.time = time.isEmpty ? "\u{2014}" : r.time
            row.locked = !time.isEmpty
            row.place = r.place.trimmingCharacters(in: .whitespaces)
            row.deltaSeconds = r.deltaSeconds
            row.deltaBetter = r.deltaBetter
            row.isEmpty = false
            return row
        }
    }

    /// A result's rank, as the web ranks it: `place_int`, else the digits of
    /// `place`; a result with neither goes after every placed one.
    private static func rank(_ r: ResultLane) -> Int {
        r.placeInt ?? Int(r.place.trimmingCharacters(in: .whitespaces)) ?? 99
    }
}
