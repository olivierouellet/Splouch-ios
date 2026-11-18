import Foundation
import Testing

@testable import SplouchCore

/// S-26: a heading where the session changes. S-27: a seed from another course.
@Suite struct SessionHeadingTests {
    func json(_ s: String) -> JSONValue { try! JSONValue.parse(s.data(using: .utf8)!) }

    func heat(_ n: String, session: Int, name: String = "") -> ScheduleHeat {
        ScheduleHeat(
            event: n, heat: "1", eventName: "", eventNameParts: nil, time: "",
            lanes: [ScheduleLane(lane: 4, name: "N", club: "C", seedTime: "", swimmers: [])],
            session: session, sessionName: name)
    }

    func visible(_ heats: [ScheduleHeat]) -> [VisibleHeat] {
        ScheduleView.visible(heats, filter: ScheduleFilter(), current: nil)
    }

    @Test func theSessionIsRead() {
        let s = Schedule(
            json: json(
                #"{"heats":[{"event":3,"heat":1,"session":2,"session_name":"Samedi pm","#
                    + #""lanes":[{"lane":4,"seed_time":"00:01:01.00","seed_course":"LCM"}]}]}"#))
        #expect(s.heats[0].session == 2)
        #expect(s.heats[0].sessionName == "Samedi pm")
        #expect(s.heats[0].lanes[0].seedCourse == "LCM")
        // An older server sends none: no heading, the seed alone.
        let old = Schedule(json: json(#"{"heats":[{"event":3,"heat":1,"lanes":[{"lane":4}]}]}"#))
        #expect(old.heats[0].session == 0 && old.heats[0].sessionName == "")
        #expect(old.heats[0].lanes[0].seedCourse == "")
    }

    @Test func aHeadingWhereTheSessionChanges() {
        let v = visible([
            heat("1", session: 1, name: "Samedi am"), heat("2", session: 1, name: "Samedi am"),
            heat("15", session: 2), heat("16", session: 0),
        ])
        let headings = v.indices.map { ScheduleView.sessionHeading(v, at: $0, word: "Séance {n}") }
        #expect(headings == ["Samedi am", nil, "Séance 2", nil])
    }

    @Test func aFilterMovesTheHeadingToTheFirstHeatLeft() {
        let v = visible([heat("2", session: 1, name: "Samedi am"), heat("3", session: 1, name: "Samedi am")])
        let filtered = Array(v.dropFirst())
        #expect(ScheduleView.sessionHeading(filtered, at: 0, word: "") == "Samedi am")
    }

    @Test func aSeedFromAnotherCourseIsItsOwnColourAndNoGap() {
        var lane = ScheduleLane(
            lane: 4, name: "N", club: "C", seedTime: "00:01:01.00", seedCourse: "LCM", swimmers: [])
        let other = LaneTime(text: "01:01.00", kind: .seedOther, spokenKey: "time_seed", spokenSuffix: "LCM")
        #expect(LaneTime.of(lane) == other)
        // Not official yet: the console's gap would be to a long-course seed.
        lane.consoleTime = "00:00:59.00"
        #expect(LaneTime.of(lane, diff: true) == other)
        lane.seedCourse = ""
        #expect(LaneTime.of(lane, diff: true)?.kind == .better)
        lane.consoleTime = ""
        #expect(LaneTime.of(lane) == LaneTime(text: "01:01.00", kind: .seed, spokenKey: "time_seed"))
    }
}
