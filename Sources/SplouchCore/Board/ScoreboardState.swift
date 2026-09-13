import Foundation

/// How a lane's time cell is styled (app.md L-11).
public enum TimeStyle: Sendable, Equatable {
    case plain
    /// The lane is running: the cell shows the race clock or waits for it.
    case running
    /// One-shot "locked" transition on the running→stopped edge. `generation`
    /// increments on every edge so a lane that finishes twice plays it twice.
    case locked(generation: Int)
}

/// One lane row of the Scoreboard tab. `numLanes` of these always exist (L-04,
/// L-09): an empty lane is blank in place, never collapsed.
public struct LaneRow: Sendable, Equatable {
    public var name = ""
    public var alt = ""
    public var club = ""
    /// What the time cell shows: a split or final from `lane_time<i>`, or the race
    /// clock while the lane is running and the clock is alive, or whatever was
    /// last painted when the clock froze.
    public var time = ""
    /// Trimmed. Empty means no place — no `#`, no dash (L-15, R-07).
    public var place = ""
    public var deltaSeconds: Double?
    public var deltaBetter: Bool?
    public var running = false
    public var timeStyle: TimeStyle = .plain
    /// The lane number cycles between row and timing colour: running, live, but
    /// no clock to show yet (L-12).
    public var pulse = false
    /// Counts running→stopped edges so each lock transition is distinct.
    var lockEdges = 0

    public init() {}
}

/// The live board (app.md §3). Pure state: the socket feeds it frames and
/// liveness, the view samples it and drives the ~10Hz tick.
///
/// Frames are partial and merge into this state (L-10). Nothing here holds a
/// state on a timer that decides what is on screen (L-21): the only clock fills
/// a cell.
public struct ScoreboardState: Sendable, Equatable {
    public typealias Instant = ContinuousClock.Instant

    public let numLanes: Int
    public private(set) var lanes: [LaneRow]
    public private(set) var currentEvent = ""
    public private(set) var currentHeat = ""
    public private(set) var eventName = ""
    public private(set) var eventNameParts: EventNameParts?
    public private(set) var heatTime = ""
    public private(set) var expectedSplits: Int?
    public private(set) var meetLive = false
    public private(set) var connected = false
    public private(set) var clock = RaceClock()

    private var lastEvent: String?
    private var lastHeat: String?

    public init(numLanes: Int) {
        self.numLanes = max(1, numLanes)
        self.lanes = Array(repeating: LaneRow(), count: self.numLanes)
    }

    /// Lane `i` is 1-indexed as on the wire.
    public subscript(lane i: Int) -> LaneRow { lanes[i - 1] }

    // MARK: - Liveness (C-09)

    /// The socket (re)connected. The reference resets its running flags and the
    /// event/heat baseline here, so the join replay lands as a fresh snapshot: no
    /// lane plays a lock flash for an edge it did not see, and nothing blanks.
    public mutating func socketConnected() {
        connected = true
        lastEvent = nil
        lastHeat = nil
        for i in lanes.indices { lanes[i].running = false }
        clock.stop()
        refreshPulses()
    }

    /// A drop implies `meet_live = false`: every clock stops so stale lane state
    /// cannot masquerade as a live race. Cells hold their last value.
    public mutating func socketDisconnected() {
        connected = false
        meetLive = false
        clock.stop()
        refreshPulses()
    }

    public mutating func setMeetLive(_ live: Bool) {
        meetLive = live
        if !live { clock.stop() }
        refreshPulses()
    }

    /// Tab or app backgrounded: stop the ticker. Ticks never accumulate across a
    /// suspend and the next re-base brings the clock back within a sync interval.
    public mutating func suspend() {
        clock.stop()
        refreshPulses()
    }

    // MARK: - Frames (L-10)

    /// Merge one `update_scoreboard` frame. Unknown keys are ignored (C-07).
    public mutating func apply(_ frame: JSONValue, at now: Instant) {
        guard let fields = frame.object else { return }
        apply(fields, at: now)
    }

    public mutating func apply(_ fields: [String: JSONValue], at now: Instant) {
        // Running flags first, as both reference boards do: they decide whether
        // the cells written below take their time from `lane_time<i>` or from the
        // clock, and at a wall the flag and the split arrive in the same frame.
        for i in 1...numLanes {
            guard let v = fields["lane_running\(i)"] else { continue }
            let isRunning = v.bool ?? false
            let was = lanes[i - 1].running
            lanes[i - 1].running = isRunning
            if isRunning {
                lanes[i - 1].timeStyle = .running
            } else if was {
                lanes[i - 1].lockEdges += 1
                lanes[i - 1].timeStyle = .locked(generation: lanes[i - 1].lockEdges)
            }
        }

        // Then the clock, so a re-base is painted before anything below can
        // stamp a stale split over it. A lane edge never touches the clock by
        // itself: the relay forces a `running_time` onto that frame.
        if let rt = fields["running_time"]?.text {
            clock.rebase(rt, at: now)
        }

        for i in 1...numLanes {
            let n = "\(i)"
            if let v = fields["lane_name" + n]?.text { lanes[i - 1].name = v }
            if let v = fields["lane_name_alt" + n]?.text { lanes[i - 1].alt = v }
            if let v = fields["lane_club" + n]?.text { lanes[i - 1].club = v }
            if let v = fields["lane_time" + n]?.text, !clockOwns(lane: i) {
                // A running lane's time cell belongs to the ticker. The split stays
                // in the server's snapshot and comes back on the join replay.
                lanes[i - 1].time = v
            }
            if let v = fields["lane_place" + n]?.text {
                lanes[i - 1].place = v.trimmingCharacters(in: .whitespaces)
            }
            if let v = fields["lane_delta_seconds" + n] { lanes[i - 1].deltaSeconds = v.double }
            if let v = fields["lane_delta_better" + n] { lanes[i - 1].deltaBetter = v.bool }
        }

        if let v = fields["event_name"]?.text { eventName = v }
        if let v = fields["event_name_parts"] { eventNameParts = EventNameParts(json: v) }
        if let v = fields["heat_time"]?.text { heatTime = v }
        if let v = fields["expected_splits"]?.int { expectedSplits = v }

        // A new event or heat blanks times, deltas and places (L-13). The first
        // value seen after a connect is a baseline, not a change: a join replay
        // must not blank the snapshot it just delivered.
        var heatChanged = false
        if let v = fields["current_event"]?.text {
            currentEvent = v
            if let last = lastEvent, last != v { heatChanged = true }
            lastEvent = v
        }
        if let v = fields["current_heat"]?.text {
            currentHeat = v
            if let last = lastHeat, last != v { heatChanged = true }
            lastHeat = v
        }
        if heatChanged { blankForNewHeat() }

        // Nothing runs a clock unless some lane is running.
        if !lanes.contains(where: \.running) { clock.stop() }

        paintClock(at: now)
        refreshPulses()
    }

    private mutating func blankForNewHeat() {
        clock.stop()
        for i in lanes.indices {
            lanes[i].time = ""
            lanes[i].place = ""
            lanes[i].deltaSeconds = nil
            lanes[i].deltaBetter = nil
            lanes[i].timeStyle = lanes[i].running ? .running : .plain
        }
    }

    // MARK: - Ticking (L-12)

    /// True while the ticker owns lane `i`'s time cell.
    public func clockOwns(lane i: Int) -> Bool {
        clock.isRunning && lanes[i - 1].running
    }

    /// Advance the race clock. Call at ~10Hz while the tab is visible, off a
    /// monotonic instant. Silence past three sync intervals freezes the digits
    /// forward and stops the ticker; the pulse takes over until the next re-base.
    public mutating func tick(at now: Instant) {
        paintClock(at: now)
        refreshPulses()
    }

    private mutating func paintClock(at now: Instant) {
        guard let reading = clock.reading(at: now) else { return }
        for i in lanes.indices where lanes[i].running {
            lanes[i].time = reading.text
        }
        if case .frozen = reading { clock.stop() }
    }

    private mutating func refreshPulses() {
        let clockAlive = clock.isRunning
        for i in lanes.indices {
            lanes[i].pulse = meetLive && lanes[i].running && !clockAlive
        }
    }
}
