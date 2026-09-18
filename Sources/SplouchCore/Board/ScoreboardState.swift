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
    /// Lengths this lane has completed (`lane_splits<i>`); `0` at the top of
    /// every heat, and `0` for a console that never raises the count at all.
    public var splits = 0
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
    /// Lengths the event runs to (distance ÷ pool length). `0` when unknown —
    /// there is then nothing to count down from (L-23).
    public private(set) var expectedSplits = 0
    /// Lengths one counted split is worth: `2` where the pool has touchpads at
    /// one end only, else `1`. A property of the venue, not of the console.
    public private(set) var splitStep = 1
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

    // MARK: - Lap count (L-23)

    /// What lane `i`'s delta cell carries while the lap is its tenant, or `nil`
    /// when the cell belongs to the delta or to nothing.
    ///
    /// Derived from merged state and from nothing else — no edge, no "when this
    /// changed". A client that joins mid-heat is handed the cached snapshot
    /// (api.md §3) with every transition already behind it, and any rule keyed
    /// to a change would read that replay as a heat where nothing ever happened.
    public func lap(lane i: Int, _ settings: LapSettings) -> LapCount? {
        guard settings.show else { return nil }
        let lane = lanes[i - 1]
        // The delta takes the cell back the moment it has something to say.
        guard DeltaFormat.text(lane.deltaSeconds).isEmpty else { return nil }
        // And the place ends the lap whatever the delta is doing: a swimmer with
        // no seed time never gets a delta at all, so waiting for one would leave
        // the lap under a finished swim for the rest of the heat.
        guard lane.place.isEmpty else { return nil }

        // Counting down needs a total to count down from. `expected_splits` is 0
        // for any event whose meet file carries no distance, and the count falls
        // back to up rather than running to a number nobody reaches.
        let countingDown = settings.direction == .down && expectedSplits > 0
        guard lane.splits > 0 || (countingDown && !lane.name.trimmingCharacters(in: .whitespaces).isEmpty) else {
            // Counting up waits for the first wall — a column of noughts under a
            // start list is noise. Counting down has the whole race to report and
            // shows from the moment the heat loads, but it needs a swimmer to say
            // it about: an empty lane in a short heat must not advertise lengths
            // nobody is swimming.
            return nil
        }

        // Clamped at 0 so a console that over-counts reads as the last length
        // rather than a negative one.
        let text = countingDown ? String(max(0, expectedSplits - lane.splits)) : String(lane.splits)
        // `+ splitStep`, never `+ 1`: with touchpads at one end only the count
        // arrives in twos and never lands on an odd length, so a `+ 1` test would
        // never fire on exactly the setup where the deck can least easily tell.
        // Once true it holds to the finish — the next thing the console reports
        // *is* the finish — and on a half-padded pool it covers the last two
        // lengths, because the swimmer is not seen in between.
        let isFinal = expectedSplits > 0 && lane.splits + splitStep >= expectedSplits
        return LapCount(text: text, isFinal: isFinal)
    }

    // MARK: - Liveness (C-09)

    /// The socket (re)connected. The reference resets its running flags and the
    /// event/heat baseline here, so the join replay lands as a fresh snapshot: no
    /// lane plays a lock flash for an edge it did not see, and nothing blanks.
    public mutating func socketConnected() {
        connected = true
        lastEvent = nil
        lastHeat = nil
        for i in lanes.indices { lanes[i].running = false }
        // The lap count's three inputs go back to "nothing known" (L-23), the
        // way the reference board's `reset_state` does: the join replay carries
        // the cached snapshot and puts back whatever is still true, and a stale
        // `expected_splits` from the last meet would otherwise count down from
        // a distance this one does not swim.
        expectedSplits = 0
        splitStep = 1
        for i in lanes.indices { lanes[i].splits = 0 }
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
        // L-13's second case reads the state before this frame.
        let wasRunning = lanes.contains(where: \.running)

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
            // L-23. `int ?? 0` rather than a guard: the server blanks the count
            // to 0 at the top of every heat, and a value that does not decode
            // is the same nothing.
            if let v = fields["lane_splits" + n] { lanes[i - 1].splits = v.int ?? 0 }
        }

        if let v = fields["event_name"]?.text { eventName = v }
        if let v = fields["event_name_parts"] { eventNameParts = EventNameParts(json: v) }
        if let v = fields["heat_time"]?.text { heatTime = v }
        // Both halves of L-23's final-stretch test describe the venue and arrive
        // together on every heat change. A `split_step` of 0 would make the test
        // fire a length early, so it floors at 1.
        if let v = fields["expected_splits"]?.int { expectedSplits = max(0, v) }
        if let v = fields["split_step"]?.int { splitStep = max(1, v) }

        // L-13, three cases. The first event/heat seen after a connect is a
        // baseline, not a change: a join replay must not blank the snapshot it
        // just delivered. A change while a lane was running on the previous
        // frame keeps every time as a result: the console advanced before it
        // published them. Otherwise the change blanks times, deltas and places.
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
        if heatChanged {
            if wasRunning {
                clock.stop()   // the ticker stops either way (L-12)
            } else {
                blankForNewHeat()
            }
        }

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
            // L-23's cell empties with the rest of the row. Every decoder blanks
            // `lane_splits<i>` in its own `reset_lanes()` and the zeros land in
            // this very frame, so in practice this changes nothing — but the
            // board already refuses to take a cleared row on trust for times,
            // places and deltas, and the lane sharing that cell should not be
            // the one field that waits for the server to say so.
            lanes[i].splits = 0
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
