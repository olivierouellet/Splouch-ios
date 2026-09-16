import Foundation
import Testing
@testable import SplouchCore

@Suite struct ResultsBoardTests {
    func lane(_ ch: Int, place: String = "", time: String = "", name: String = "N\(UUID().uuidString.prefix(2))") -> ResultLane {
        ResultLane(channel: ch, place: place, placeInt: Int(place), time: time, name: name, club: "C", alt: "",
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
        let snap = ResultsSnapshot(event: "3", heat: "1", eventName: "x", eventNameParts: nil, sort: .lane,
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
        let snap = ResultsSnapshot(event: "3", heat: "1", eventName: "", eventNameParts: nil, sort: nil,
                                   lanes: [lane(5, place: "1", time: "1.00", name: "A")])
        let rows = ResultsBoard.rows(snap, numLanes: 8)
        #expect(rows[4].name == "A")
        #expect(rows[0].isEmpty)
    }

    @Test func placeSortFillsTopDown() {
        let snap = ResultsSnapshot(event: "3", heat: "1", eventName: "", eventNameParts: nil, sort: .place,
                                   lanes: [lane(4, place: "1", time: "1.00", name: "A"), lane(2, place: "2", time: "2.00", name: "B")])
        let rows = ResultsBoard.rows(snap, numLanes: 4)
        #expect(rows[0].name == "A" && rows[0].laneLabel == "4")
        #expect(rows[1].name == "B" && rows[1].laneLabel == "2")
        #expect(rows[2].isEmpty && rows[2].laneLabel == "—")
    }

    @Test func missingTimeIsDashAndMissingPlaceIsEmpty() {
        let snap = ResultsSnapshot(event: "3", heat: "1", eventName: "", eventNameParts: nil, sort: .lane,
                                   lanes: [lane(1, place: " ", time: " ", name: "A")])
        let row = ResultsBoard.rows(snap, numLanes: 2)[0]
        #expect(row.time == "—")
        #expect(row.place == "")
        #expect(!row.locked)
        #expect(!row.isEmpty)
    }

    @Test func channelOutsideTheBoardIsDropped() {
        let snap = ResultsSnapshot(event: "3", heat: "1", eventName: "", eventNameParts: nil, sort: .lane,
                                   lanes: [lane(9, place: "1", time: "1.00"), lane(0, place: "2", time: "1.00")])
        #expect(ResultsBoard.rows(snap, numLanes: 8).allSatisfy { $0.isEmpty })
    }
}

@Suite struct ScheduleFilterTests {
    func lane(_ n: Int, _ name: String, club: String, swimmers: [String] = []) -> ScheduleLane {
        ScheduleLane(lane: n, name: name, club: club, seedTime: "",
                     swimmers: swimmers.map { ScheduleSwimmer(name: $0, first: String($0.split(separator: " ").last ?? "")) })
    }
    var heats: [ScheduleHeat] {
        [
            ScheduleHeat(event: "1", heat: "1", eventName: "", eventNameParts: nil, time: "9:00",
                         lanes: [lane(1, "Doe, Jane", club: "CAMO"), lane(2, "Roe, Rick", club: "PCSC")]),
            ScheduleHeat(event: "1", heat: "2", eventName: "", eventNameParts: nil, time: "9:05",
                         lanes: [lane(3, "Poe, Ann", club: "PCSC")]),
            ScheduleHeat(event: "2", heat: "1", eventName: "", eventNameParts: nil, time: "9:10",
                         lanes: [lane(4, "CAMO A", club: "CAMO", swimmers: ["Doe Jane", "Foo Bar"])]),
            ScheduleHeat(event: "3", heat: "1", eventName: "", eventNameParts: nil, time: "", lanes: []),
        ]
    }

    /// The seed column is sized from the widest time on screen, so the club
    /// beside it lands in the same place on every row.
    @Test func widestSeedTimeSizesTheColumn() {
        func heat(_ times: [String]) -> ScheduleHeat {
            ScheduleHeat(event: "1", heat: "1", eventName: "", eventNameParts: nil, time: "",
                         lanes: times.enumerated().map { i, t in
                             ScheduleLane(lane: i + 1, name: "N", club: "C", seedTime: t, swimmers: [])
                         })
        }
        func widest(_ heats: [ScheduleHeat]) -> String {
            ScheduleView.widestSeedTime(ScheduleView.visible(heats, filter: ScheduleFilter(), current: nil))
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
        let f = ScheduleFilter(terms: [.init(kind: .club, name: "PCSC"), .init(kind: .swimmer, name: "Doe, Jane")])
        let v = ScheduleView.visible(heats, filter: f, current: nil)
        #expect(v.map { $0.heat.heat + "@" + $0.heat.event } == ["1@1", "2@1"])
        #expect(v[0].lanes.map(\.lane) == [1, 2])
        #expect(v[1].lanes.map(\.lane) == [3])
        #expect(v.map(\.stripe) == [0, 1])
    }

    @Test func swimmerFilterMatchesRelayMembers() {
        let f = ScheduleFilter(terms: [.init(kind: .swimmer, name: "Foo Bar")])
        let v = ScheduleView.visible(heats, filter: f, current: nil)
        #expect(v.count == 1)
        #expect(v[0].heat.event == "2")
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
        var f = ScheduleFilter(terms: [.init(kind: .swimmer, name: "Foo Bar"), .init(kind: .swimmer, name: "Gone"), .init(kind: .club, name: "CAMO")], showAllHeats: true)
        f.prune(to: heats)
        #expect(f.terms.map(\.name) == ["Foo Bar", "CAMO"])
        #expect(f.showAllHeats)
    }

    @Test func relayDisplayNameJoinsFirstNames() {
        #expect(ScheduleView.displayName(lane(4, "CAMO A", club: "CAMO", swimmers: ["Doe Jane", "Foo Bar"])) == "Jane · Bar")
        #expect(ScheduleView.displayName(lane(1, "Doe, Jane", club: "CAMO")) == "Doe, Jane")
        #expect(ScheduleView.displayName(lane(1, "", club: "")) == "—")
        var l = lane(4, "Relay", club: "C", swimmers: ["X"])
        l.swimmers[0].first = ""
        #expect(ScheduleView.displayName(l) == "X")
    }
}
