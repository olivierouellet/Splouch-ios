import Testing
@testable import SplouchCore
@testable import SplouchUI

/// L-07 / L-08 / L-23. Which columns and which headers a board draws is the
/// operator's settings turned into six booleans, and it is the one piece of the
/// board that can be checked without drawing anything.
@Suite struct ColumnsTests {
    @Test func theOperatorsSettingsDecideTheColumns() {
        let all = Columns(MeetSettings())
        #expect(all.name && all.club && all.delta && all.place)

        let bare = Columns(MeetSettings(showName: false, showClub: false, showDelta: false, showPosition: false))
        #expect(!bare.name && !bare.club && !bare.delta && !bare.place)
        // Hiding a column is not hiding its header — they are separate settings,
        // and a board with headers off still shows the columns.
        #expect(bare.nameHeader && bare.clubHeader && bare.placeHeader)
    }

    @Test func headersAreTheirOwnSettings() {
        let noHeaders = Columns(MeetSettings(showLaneHeader: false, showNameHeader: false, showClubHeader: false,
                                             showTimeHeader: false, showDeltaHeader: false, showPositionHeader: false))
        #expect(!noHeaders.laneHeader && !noHeaders.nameHeader && !noHeaders.clubHeader)
        #expect(!noHeaders.timeHeader && !noHeaders.deltaHeader && !noHeaders.placeHeader)
        #expect(noHeaders.name && noHeaders.club)   // the columns themselves are untouched
    }

    /// L-23: with laps on, the delta cell holds lengths for most of a heat, and
    /// a `Δ` over a column of small integers is a claim about them. The header
    /// goes, and it stays gone once the heat settles — a title appearing at the
    /// finish would be the moving header L-23 exists to refuse.
    @Test func theDeltaHeaderGoesWhenTheLapCountSharesItsCell() {
        let on = Columns(MeetSettings(), laps: LapSettings(show: true))
        #expect(!on.deltaHeader)
        #expect(on.delta, "the column stays; only its title goes")
        // Every other header is untouched by the lap count.
        #expect(on.nameHeader && on.clubHeader && on.placeHeader && on.laneHeader && on.timeHeader)

        let off = Columns(MeetSettings(), laps: .off)
        #expect(off.deltaHeader)
    }

    /// The Results tab is all finishes, so its delta column has one tenant and
    /// keeps its title — it never passes a lap setting at all.
    @Test func theResultsBoardKeepsItsDeltaHeader() {
        #expect(Columns(MeetSettings()).deltaHeader)
        // And an operator who turned the header off still gets it off.
        #expect(!Columns(MeetSettings(showDeltaHeader: false)).deltaHeader)
        // With laps on *and* the header off, it is off for both reasons.
        #expect(!Columns(MeetSettings(showDeltaHeader: false), laps: LapSettings(show: true)).deltaHeader)
    }
}

/// R-04: the Scoreboard tab's `LaneRow` and the Results tab's `ResultRow` are
/// different models of the same six columns, and this is where they meet.
@Suite struct BoardRowTests {
    @Test func aLaneRowKeepsItsLaneNumberAndItsCells() {
        var lane = LaneRow()
        lane.name = "Tremblay"
        lane.club = "CNQ"
        lane.alt = "T."
        lane.time = "1:02.30"
        lane.place = "2"
        lane.deltaSeconds = 1.25
        lane.deltaBetter = false
        lane.pulse = true

        let row = BoardRow(4, lane)
        #expect(row.laneLabel == "4")
        #expect(row.name == "Tremblay")
        #expect(row.club == "CNQ")
        #expect(row.alt == "T.")
        #expect(row.time == "1:02.30")
        #expect(row.place == "2")
        #expect(row.deltaBetter == false)
        #expect(row.pulse)
        // The delta is formatted on the way in, not stored as a number.
        #expect(row.delta == DeltaFormat.text(1.25))
        #expect(row.lap == nil)
    }

    /// L-23's other tenant. A lane row can carry one; a result row cannot.
    @Test func onlyTheLiveBoardCarriesALapCount() {
        let withLap = BoardRow(1, LaneRow(), lap: LapCount(text: "3", isFinal: false))
        #expect(withLap.lap?.text == "3")
        #expect(withLap.lap?.isFinal == false)
        #expect(BoardRow(1, LaneRow()).lap == nil)
        #expect(BoardRow(ResultRow(laneLabel: "1")).lap == nil)
    }

    /// R-09: a final time is styled locked. A row that is not final is plain,
    /// and the lane label is the result's own — which may be a `—` for an
    /// unfilled row of a ranking, not a lane number.
    @Test func aResultRowCarriesItsOwnLabelAndItsLockedStyling() {
        var result = ResultRow(laneLabel: "3")
        result.name = "Roy"
        result.time = "58.11"
        result.place = "1"
        result.deltaSeconds = -0.4
        result.deltaBetter = true
        result.locked = true

        let row = BoardRow(result)
        #expect(row.laneLabel == "3")
        #expect(row.name == "Roy")
        #expect(row.time == "58.11")
        #expect(row.delta == DeltaFormat.text(-0.4))
        #expect(row.deltaBetter == true)
        if case .locked = row.timeStyle {} else { Issue.record("a final time should be locked") }

        var running = ResultRow(laneLabel: "\u{2014}")
        running.locked = false
        #expect(BoardRow(running).laneLabel == "\u{2014}")
        #expect(BoardRow(running).timeStyle == .plain)
    }
}

/// The tab keys are the join with the server's `mobile` strings, and the list
/// identity the schedule scrolls by.
@Suite struct ShellIdentityTests {
    @Test func tabKeysAreTheKeysTheServerServes() {
        #expect(MeetTab.allCases.map(\.key) == ["scoreboard", "results", "schedule"])
        // The key is the raw value, so a tab renamed in Swift alone would stop
        // resolving its own label — SnapshotCoverageTests checks the other end.
        #expect(MeetTab.scoreboard.key == MeetTab.scoreboard.rawValue)
        #expect(MeetTab.allCases.allSatisfy { !$0.symbol.isEmpty })
        #expect(Set(MeetTab.allCases.map(\.symbol)).count == 3)
    }

    /// A heat is identified by event and heat together: heat 1 exists in every
    /// event, so the number alone would collapse the whole schedule to a few rows.
    @Test func aHeatIsIdentifiedByItsEventAndItsHeat() {
        func heat(_ event: String, _ heat: String) -> ScheduleHeat {
            ScheduleHeat(event: event, heat: heat, eventName: "", time: "", lanes: [])
        }
        let a = heat("1", "1")
        let b = heat("2", "1")
        let c = heat("1", "2")
        #expect(a.id != b.id)
        #expect(a.id != c.id)
        #expect(a.id == heat("1", "1").id)
    }
}
