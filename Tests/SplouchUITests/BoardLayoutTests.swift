import CoreGraphics
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
        let noHeaders = Columns(
            MeetSettings(
                showLaneHeader: false, showNameHeader: false, showClubHeader: false,
                showTimeHeader: false, showDeltaHeader: false, showPositionHeader: false))
        #expect(!noHeaders.laneHeader && !noHeaders.nameHeader && !noHeaders.clubHeader)
        #expect(!noHeaders.timeHeader && !noHeaders.deltaHeader && !noHeaders.placeHeader)
        #expect(noHeaders.name && noHeaders.club)  // the columns themselves are untouched
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

/// L-15 / L-16 / L-17: the board's sizes as numbers — the same rules the web
/// board writes down in `scoreboard_base.html`.
@Suite struct BoardFitTests {
    /// L-16: 55% of each lane's share, from 11pt up to 56 — no longer 32, which
    /// left most of a tablet row empty.
    @Test func theRowFontIsCappedAt56() {
        // Four lanes on a 13" iPad in landscape: far past the cap.
        let tablet = BoardFit.landscapeType(height: 900, lanes: 4)
        #expect(tablet.rowFont == 56)
        #expect(tablet.showsHeader)
        // Six lanes on a phone on its side: under the cap, and 0.55 of the share
        // left once the title band is withheld.
        let phone = BoardFit.landscapeType(height: 330, lanes: 6)
        #expect(abs(phone.rowFont - (330 - BoardFit.headerBand) * 0.55 / 6) < 0.001)
        #expect(phone.showsHeader)
    }

    /// The titles go when keeping them would set the lanes under 14pt; the rows
    /// are then sized over the whole height, floored at 11.
    @Test func aShortBoardDropsItsTitlesFirst() {
        let crowded = BoardFit.landscapeType(height: 300, lanes: 12)
        #expect(!crowded.showsHeader)
        #expect(abs(crowded.rowFont - 300 * 0.55 / 12) < 0.001)
        #expect(BoardFit.landscapeType(height: 100, lanes: 10).rowFont == 11)
    }

    /// Bigger rows must not grow the title row past the band the rows were
    /// sized without: its type stops where the band does.
    @Test func theTitleRowStaysInsideItsBand() {
        #expect(BoardFit.headerFont(56) == BoardFit.headerFontRange.upperBound)
        #expect(BoardFit.headerFont(11) == 10)
        // A line of the largest title type, with its padding, fits the band.
        #expect(BoardFit.headerFontRange.upperBound * 1.3 + 4 <= BoardFit.headerBand)
    }

    /// L-15: the narrow board's base is 0.26 of each lane's share, 13…24 —
    /// a function of the share alone, so measuring a row cannot move it.
    @Test func theNarrowBaseComesFromTheShare() {
        #expect(BoardFit.portraitBase(share: 80) == 80 * 0.26)
        #expect(BoardFit.portraitBase(share: 30) == 13)
        #expect(BoardFit.portraitBase(share: 200) == 24)
    }

    /// One factor per column, from its widest case: 1 when it fits, the ratio
    /// with a little air when it doesn't, never under half.
    @Test func aColumnFitsItsWidestCase() {
        #expect(BoardFit.columnFit(room: 120, need: 100) == 1)
        #expect(abs(BoardFit.columnFit(room: 100, need: 125) - 0.8 * 0.97) < 0.0001)
        #expect(BoardFit.columnFit(room: 10, need: 100) == 0.5)
        // Before the first layout there is no room to fit to.
        #expect(BoardFit.columnFit(room: 0, need: 100) == 1)
    }

    /// The time column is fitted to the template, not to the value: the clock
    /// running from 59.9 to 1:00.0 must not move its size, and a 1500 fits the
    /// template.
    @Test @MainActor func theTimeIsFittedToItsTemplate() {
        let faces = Faces(ThemeFonts())
        let template = faces.timingWidth(BoardFit.timeTemplate, size: 30)
        #expect(faces.timingWidth("18:05.33", size: 30) <= template)
        #expect(faces.timingWidth("1:00.0", size: 30) <= template)
        // 17% of a 600pt row is 102pt; a 30pt time does not fit that and shrinks.
        let room = TableColumns(width: 600, columns: Columns(MeetSettings())).time
        let fit = BoardFit.columnFit(room: room, need: template)
        #expect(fit < 1 && fit >= 0.5)
        #expect(template * fit <= room)
    }

    /// L-17: a name or club shrinks to half, and never under 10pt.
    @Test func aNameShrinksToHalfButNotUnder10() {
        #expect(BoardFit.nameFloor(40) == 0.5)
        #expect(BoardFit.nameFloor(16) == 10.0 / 16)
        #expect(BoardFit.nameFloor(9) == 1)
    }
}

/// L-16: the full table's columns are shares of the row, and the title row and
/// the lanes read them from the same place.
@Suite struct TableColumnsTests {
    @Test func theSharesAreFractionsOfTheRow() {
        let w = TableColumns(width: 1016, columns: Columns(MeetSettings()))
        let inner: CGFloat = 1000
        #expect(abs(w.lane - inner * 0.06) < 0.001)
        #expect(abs(w.club - inner * 0.14) < 0.001)
        #expect(abs(w.time - inner * 0.17) < 0.001)
        #expect(abs(w.delta - inner * 0.12) < 0.001)
        #expect(abs(w.place - inner * 0.06) < 0.001)
        #expect(abs(w.name - (inner * 0.45 - 5 * TableColumns.gap)) < 0.001)
    }

    /// Every show_* combination fills the row exactly: a hidden column is 0 and
    /// its share goes to the name — or, with no name, to the columns that show.
    @Test(arguments: 0..<16) func everyCombinationFillsTheRow(_ mask: Int) {
        let settings = MeetSettings(
            showName: mask & 1 != 0, showClub: mask & 2 != 0, showDelta: mask & 4 != 0,
            showPosition: mask & 8 != 0)
        let columns = Columns(settings)
        let w = TableColumns(width: 800, columns: columns)
        #expect(abs(w.total - (800 - 2 * TableColumns.inset)) < 0.001)
        #expect((w.name > 0) == columns.name)
        #expect((w.club > 0) == columns.club)
        #expect((w.delta > 0) == columns.delta)
        #expect((w.place > 0) == columns.place)
        #expect(w.lane > 0 && w.time > 0)
        if columns.name {
            // The fixed columns keep their shares whatever else is hidden.
            #expect(abs(w.time - 784 * TableColumns.timeShare) < 0.001)
        }
    }
}

/// L-02: the event name grows on an iPad and holds still on every iPhone.
@Suite struct BoardHeaderTests {
    @Test func theEventNameGrowsOnlyPastTheWidestIPhone() {
        for phone: CGFloat in [0, 375, 402, 440] {
            #expect(BoardHeader.eventNameSize(width: phone, compact: false) == 16)
        }
        #expect(BoardHeader.eventNameSize(width: 660, compact: false) == 24)
        #expect(BoardHeader.eventNameSize(width: 1032, compact: false) == 24)
        let mid = BoardHeader.eventNameSize(width: 550, compact: false)
        #expect(mid > 16 && mid < 24)
        #expect(BoardHeader.eventNameSize(width: 1376, compact: true) == 13)
    }
}
