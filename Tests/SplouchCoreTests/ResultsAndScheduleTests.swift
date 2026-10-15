import Foundation
import Testing

@testable import SplouchCore

@Suite struct ResultsBoardTests {
    func lane(_ ch: Int, place: String = "", time: String = "", name: String = "N\(UUID().uuidString.prefix(2))")
        -> ResultLane
    {
        ResultLane(
            channel: ch, place: place, placeInt: Int(place), time: time, name: name, club: "C", alt: "",
            deltaSeconds: nil, deltaBetter: nil)
    }

    @Test func emptyGridHasNumLanesRows() {
        let rows = ResultsBoard.empty(numLanes: 6)
        #expect(rows.count == 6)
        #expect(rows.allSatisfy { $0.isEmpty })
        #expect(rows[2].laneLabel == "3")
        #expect(rows[2].time == "—")
        #expect(rows[2].place == "")
    }

    @Test func laneSortPlacesByChannelAndLeavesGaps() {
        let snap = ResultsSnapshot(
            event: "3", heat: "1", eventName: "x", eventNameParts: nil, sort: .lane,
            lanes: [lane(4, place: "1", time: "2:20.92", name: "A"), lane(2, place: "2", time: "2:21.00", name: "B")])
        let rows = ResultsBoard.rows(snap, numLanes: 6)
        #expect(rows[3].name == "A")
        #expect(rows[1].name == "B")
        #expect(rows[0].isEmpty && rows[0].laneLabel == "1" && rows[0].time == "—")
        #expect(rows[3].laneLabel == "4")
        #expect(rows[3].locked)
        #expect(rows[3].place == "1")
    }

    @Test func absentSortIsLaneNeverPlace() {
        let snap = ResultsSnapshot(
            event: "3", heat: "1", eventName: "", eventNameParts: nil, sort: nil,
            lanes: [lane(5, place: "1", time: "1.00", name: "A")])
        let rows = ResultsBoard.rows(snap, numLanes: 8)
        #expect(rows[4].name == "A")
        #expect(rows[0].isEmpty)
    }

    /// P-23: a reader who wants places ranks a heat the pool sorted by lane.
    @Test func readersPlaceOrderRanksALaneSortedSnapshot() {
        let snap = ResultsSnapshot(
            event: "3", heat: "1", eventName: "", eventNameParts: nil, sort: .lane,
            lanes: [
                lane(1, place: "", time: "", name: "DQ"), lane(2, place: "2", time: "2.00", name: "B"),
                lane(3, place: "1", time: "1.00", name: "A"),
            ])
        let rows = ResultsBoard.rows(snap, numLanes: 4, order: .place)
        #expect(rows.map(\.name) == ["A", "B", "DQ", ""])
        #expect(rows.map(\.slot) == [1, 2, 3, 4])
        #expect(rows[3].laneLabel.isEmpty)
    }

    /// P-23: and one who wants lanes puts a place-sorted heat back on its lanes.
    @Test func readersLaneOrderOutranksThePoolsPlaceOrder() {
        let snap = ResultsSnapshot(
            event: "3", heat: "1", eventName: "", eventNameParts: nil, sort: .place,
            lanes: [lane(4, place: "1", time: "1.00", name: "A"), lane(2, place: "2", time: "2.00", name: "B")])
        let rows = ResultsBoard.rows(snap, numLanes: 4, order: .lane)
        #expect(rows.map(\.name) == ["", "B", "", "A"])
    }

    /// L-26: lane order turned around keeps each row's lane and identity; a
    /// ranking is never turned around.
    @Test func descendingTurnsLanesAroundButNotARanking() {
        let snap = ResultsSnapshot(
            event: "3", heat: "1", eventName: "", eventNameParts: nil, sort: .lane,
            lanes: [lane(1, place: "2", time: "2.00", name: "B"), lane(3, place: "1", time: "1.00", name: "A")])
        let down = ResultsBoard.rows(snap, numLanes: 4, firstLane: 0, descending: true)
        #expect(down.map(\.laneLabel) == ["3", "2", "1", "0"])
        #expect(down.map(\.slot) == [4, 3, 2, 1])
        #expect(down[0].name == "A" && down[2].name == "B")
        let ranked = ResultsBoard.rows(snap, numLanes: 4, order: .place, descending: true)
        #expect(ranked.map(\.name) == ["A", "B", "", ""])
    }

    @Test func placeSortFillsTopDown() {
        let snap = ResultsSnapshot(
            event: "3", heat: "1", eventName: "", eventNameParts: nil, sort: .place,
            lanes: [lane(4, place: "1", time: "1.00", name: "A"), lane(2, place: "2", time: "2.00", name: "B")])
        let rows = ResultsBoard.rows(snap, numLanes: 4)
        #expect(rows[0].name == "A" && rows[0].laneLabel == "4")
        #expect(rows[1].name == "B" && rows[1].laneLabel == "2")
        #expect(rows[2].isEmpty && rows[2].laneLabel.isEmpty)
    }

    @Test func missingTimeIsDashAndMissingPlaceIsEmpty() {
        let snap = ResultsSnapshot(
            event: "3", heat: "1", eventName: "", eventNameParts: nil, sort: .lane,
            lanes: [lane(1, place: " ", time: " ", name: "A")])
        let row = ResultsBoard.rows(snap, numLanes: 2)[0]
        #expect(row.time == "—")
        #expect(row.place == "")
        #expect(!row.locked)
        #expect(!row.isEmpty)
    }

    @Test func channelOutsideTheBoardIsDropped() {
        let snap = ResultsSnapshot(
            event: "3", heat: "1", eventName: "", eventNameParts: nil, sort: .lane,
            lanes: [lane(9, place: "1", time: "1.00"), lane(0, place: "2", time: "1.00")])
        #expect(ResultsBoard.rows(snap, numLanes: 8).allSatisfy { $0.isEmpty })
    }

    // L-04 / api.md §5.2: in a pool numbered from 0, channel 0 is a real lane on
    // row 1, and every row is labelled with its pool lane.
    @Test func laneSortFromLaneZeroPutsChannelZeroOnTheFirstRow() {
        let snap = ResultsSnapshot(
            event: "3", heat: "1", eventName: "", eventNameParts: nil, sort: .lane,
            lanes: [
                lane(0, place: "2", time: "1.00", name: "A"), lane(3, place: "1", time: "0.90", name: "B"),
                lane(8, place: "3", time: "1.10", name: "C"),
            ])
        let rows = ResultsBoard.rows(snap, numLanes: 8, firstLane: 0)
        #expect(rows.count == 8)
        #expect(rows[0].name == "A" && rows[0].laneLabel == "0" && !rows[0].isEmpty)
        #expect(rows[3].name == "B" && rows[3].laneLabel == "3")
        #expect(rows[1].isEmpty && rows[1].laneLabel == "1")
        #expect(rows[7].isEmpty && rows[7].laneLabel == "7")
        // Lane 8 is past a 0…7 board.
        #expect(!rows.contains { $0.name == "C" })
    }

    @Test func placeSortFromLaneZeroLabelsChannelZero() {
        let snap = ResultsSnapshot(
            event: "3", heat: "1", eventName: "", eventNameParts: nil, sort: .place,
            lanes: [lane(0, place: "1", time: "1.00", name: "A")])
        let rows = ResultsBoard.rows(snap, numLanes: 3, firstLane: 0)
        #expect(rows[0].name == "A" && rows[0].laneLabel == "0")
        // R-06: unfilled ranks still show no lane number.
        #expect(rows[1].isEmpty && rows[1].laneLabel.isEmpty)
    }

    @Test func emptyGridFromLaneZeroStartsAtZero() {
        let rows = ResultsBoard.empty(numLanes: 4, firstLane: 0)
        #expect(rows.map(\.laneLabel) == ["0", "1", "2", "3"])
    }
}

@Suite struct ScheduleFilterTests {
    func lane(_ n: Int, _ name: String, club: String, swimmers: [String] = []) -> ScheduleLane {
        ScheduleLane(
            lane: n, name: name, club: club, seedTime: "",
            swimmers: swimmers.map { ScheduleSwimmer(name: $0, first: String($0.split(separator: " ").last ?? "")) })
    }
    var heats: [ScheduleHeat] {
        [
            ScheduleHeat(
                event: "1", heat: "1", eventName: "", eventNameParts: nil, time: "9:00",
                lanes: [lane(1, "Doe, Jane", club: "CAMO"), lane(2, "Roe, Rick", club: "PCSC")]),
            ScheduleHeat(
                event: "1", heat: "2", eventName: "", eventNameParts: nil, time: "9:05",
                lanes: [lane(3, "Poe, Ann", club: "PCSC")]),
            ScheduleHeat(
                event: "2", heat: "1", eventName: "", eventNameParts: nil, time: "9:10",
                lanes: [lane(4, "CAMO A", club: "CAMO", swimmers: ["Doe Jane", "Foo Bar"])]),
            ScheduleHeat(event: "3", heat: "1", eventName: "", eventNameParts: nil, time: "", lanes: []),
        ]
    }

    /// The seed column is sized from the widest time on screen, so the club
    /// beside it lands in the same place on every row.
    @Test func widestTimeSizesTheColumn() {
        func heat(_ times: [String]) -> ScheduleHeat {
            ScheduleHeat(
                event: "1", heat: "1", eventName: "", eventNameParts: nil, time: "",
                lanes: times.enumerated().map { i, t in
                    ScheduleLane(lane: i + 1, name: "N", club: "C", seedTime: t, swimmers: [])
                })
        }
        func widest(_ heats: [ScheduleHeat]) -> String {
            ScheduleView.widestTime(ScheduleView.visible(heats, filter: ScheduleFilter(), current: nil))
        }
        // Across cards, not within one: the column spans the whole screen.
        #expect(widest([heat(["NT", "57.40"]), heat(["1:04.219"])]) == "1:04.219")
        // "NT" is the widest thing there is when nothing else has a time, so a
        // meet with no seed times reserves two characters rather than eight.
        #expect(widest([heat(["NT", "NT"])]) == "NT")
        // Nothing on screen carries one: no column at all.
        #expect(widest([heat(["", ""])]) == "")
        #expect(widest([]) == "")
        // A lane with no time still sits in the column the others set.
        #expect(widest([heat(["", "1:02.41"])]) == "1:02.41")
    }

    @Test func noFilterShowsEverythingWithStripes() {
        let v = ScheduleView.visible(heats, filter: ScheduleFilter(), current: nil)
        #expect(v.count == 4)
        #expect(v.map(\.stripe) == [0, 1, 2, 3])
        #expect(v.allSatisfy { !$0.isCurrent })
    }

    @Test func filtersAreORedAndHideEmptyHeats() {
        let f = ScheduleFilter(terms: [
            .init(kind: .club, name: "PCSC"), .init(kind: .swimmer, name: "Doe, Jane", club: "CAMO"),
        ])
        let v = ScheduleView.visible(heats, filter: f, current: nil)
        #expect(v.map { $0.heat.heat + "@" + $0.heat.event } == ["1@1", "2@1"])
        #expect(v[0].lanes.map(\.lane) == [1, 2])
        #expect(v[1].lanes.map(\.lane) == [3])
        #expect(v.map(\.stripe) == [0, 1])
    }

    @Test func swimmerFilterMatchesRelayMembers() {
        let f = ScheduleFilter(terms: [.init(kind: .swimmer, name: "Foo Bar", club: "CAMO")])
        let v = ScheduleView.visible(heats, filter: f, current: nil)
        #expect(v.count == 1)
        #expect(v[0].heat.event == "2")
    }

    /// S-13: two swimmers of one name in two clubs are two people; following
    /// one does not bring the other's heat along.
    @Test func swimmerFilterMatchesOnlyItsOwnClub() {
        let h = [
            ScheduleHeat(
                event: "2", heat: "1", eventName: "", eventNameParts: nil, time: "",
                lanes: [
                    lane(3, "Olivia Gagné", club: "PPO"),
                    lane(4, "PPO A", club: "PPO", swimmers: ["Olivia Gagné"]),
                ]),
            ScheduleHeat(
                event: "3", heat: "1", eventName: "", eventNameParts: nil, time: "",
                lanes: [lane(5, "Olivia Gagné", club: "CNQ")]),
        ]
        let cnq = ScheduleFilter(terms: [.init(kind: .swimmer, name: "Olivia Gagné", club: "CNQ")])
        #expect(ScheduleView.visible(h, filter: cnq, current: nil).map(\.heat.event) == ["3"])
        let ppo = ScheduleFilter(terms: [.init(kind: .swimmer, name: "Olivia Gagné", club: "PPO")])
        #expect(ScheduleView.visible(h, filter: ppo, current: nil).flatMap { $0.lanes.map(\.lane) } == [3, 4])
    }

    @Test func allHeatsKeepsHeatsButStillFiltersLanes() {
        let f = ScheduleFilter(terms: [.init(kind: .club, name: "PCSC")], showAllHeats: true)
        let v = ScheduleView.visible(heats, filter: f, current: nil)
        #expect(v.count == 4)
        #expect(v[0].lanes.map(\.lane) == [2])
        #expect(v[2].lanes.isEmpty)
    }

    @Test func currentHeatIsHighlightedByEventAndHeat() {
        let v = ScheduleView.visible(heats, filter: ScheduleFilter(), current: HeatRef(event: " 1", heat: "2 "))
        #expect(v.map(\.isCurrent) == [false, true, false, false])
    }

    @Test func upcomingCutsByPositionNotTime() {
        let f = ScheduleFilter(upcomingOnly: true)
        let v = ScheduleView.visible(heats, filter: f, current: HeatRef(event: "2", heat: "1"))
        #expect(v.map(\.heat.event) == ["2", "3"])
        #expect(v[0].isCurrent)
        #expect(v.map(\.stripe) == [0, 1])
    }

    @Test func upcomingChangesNothingWhenCurrentUnknownOrAbsent() {
        let f = ScheduleFilter(upcomingOnly: true)
        #expect(ScheduleView.visible(heats, filter: f, current: nil).count == 4)
        #expect(ScheduleView.visible(heats, filter: f, current: HeatRef(event: "9", heat: "9")).count == 4)
    }

    @Test func addRemoveResetAndCount() {
        var f = ScheduleFilter()
        f.add(.init(kind: .club, name: "CAMO"))
        f.add(.init(kind: .club, name: "CAMO"))
        #expect(f.count == 1)
        #expect(f.contains(.init(kind: .club, name: "CAMO")))
        f.showAllHeats = true
        f.remove(.init(kind: .club, name: "CAMO"))
        #expect(!f.isFiltering)
        f.upcomingOnly = true
        f.reset()
        #expect(f == ScheduleFilter())
    }

    @Test func pruneKeepsFiltersThatStillMatchTheNewSchedule() {
        var f = ScheduleFilter(
            terms: [
                .init(kind: .swimmer, name: "Foo Bar", club: "CAMO"), .init(kind: .swimmer, name: "Gone", club: "CAMO"),
                // The name is still there, but not in this club.
                .init(kind: .swimmer, name: "Poe, Ann", club: "CAMO"),
                .init(kind: .club, name: "CAMO"),
            ], showAllHeats: true)
        f.prune(to: heats)
        #expect(f.terms.map(\.name) == ["Foo Bar", "CAMO"])
        #expect(f.showAllHeats)
    }

    @Test func relayDisplayNameJoinsFirstNames() {
        #expect(
            ScheduleView.displayName(lane(4, "CAMO A", club: "CAMO", swimmers: ["Doe Jane", "Foo Bar"])) == "Jane · Bar"
        )
        #expect(ScheduleView.displayName(lane(1, "Doe, Jane", club: "CAMO")) == "Doe, Jane")
        #expect(ScheduleView.displayName(lane(1, "", club: "")) == "—")
        var l = lane(4, "Relay", club: "C", swimmers: ["X"])
        l.swimmers[0].first = ""
        #expect(ScheduleView.displayName(l) == "X")
    }
}
