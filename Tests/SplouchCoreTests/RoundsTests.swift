import Foundation
import Testing

@testable import SplouchCore

/// S-24: a prelim and its final under one event number, two cards apart.
@Suite struct RoundsTests {
    func json(_ s: String) -> JSONValue { try! JSONValue.parse(s.data(using: .utf8)!) }

    func heat(_ round: String, lanes: [Int] = [4]) -> ScheduleHeat {
        ScheduleHeat(
            event: "15", heat: "1", round: round, eventName: "", eventNameParts: nil, time: "",
            lanes: lanes.map { ScheduleLane(lane: $0, name: "N", club: "C", seedTime: "", swimmers: []) })
    }

    @Test func theRoundIsReadFromEveryPayload() {
        let schedule = Schedule(json: json(#"{"heats":[{"event":15,"heat":1,"round":"final","lanes":[]}]}"#))
        #expect(schedule.heats[0].round == "final")
        #expect(ResultsSnapshot(json: json(#"{"event":"15","heat":"1","round":"prelims"}"#)).round == "prelims")
        // An older server sends none: one round.
        #expect(Schedule(json: json(#"{"heats":[{"event":3,"heat":1,"lanes":[]}]}"#)).heats[0].round == "")
    }

    @Test func theBoardKeepsTheCurrentRound() {
        var s = ScoreboardState(numLanes: 2)
        s.apply(json(#"{"current_event":"15","current_heat":"1","current_round":"final"}"#), at: .now)
        #expect(s.currentRound == "final")
        s.reset()
        #expect(s.currentRound == "")
    }

    @Test func onlyTheCurrentRoundIsHighlighted() {
        let heats = [heat("prelims"), heat("final")]
        let v = ScheduleView.visible(
            heats, filter: ScheduleFilter(), current: HeatRef(event: "15", heat: "1", round: "final"))
        #expect(v.map(\.isCurrent) == [false, true])
    }

    @Test func consoleTimesLandOnTheirRound() {
        var schedule = Schedule(heats: [heat("prelims"), heat("final")])
        let snap = ResultsSnapshot(
            json: json(#"{"event":"15","heat":"1","round":"final","lanes":[{"channel":4,"time":"59.90"}]}"#))
        schedule.applyConsoleTimes(snap)
        #expect(schedule.heats[0].lanes[0].consoleTime == "")
        #expect(schedule.heats[1].lanes[0].consoleTime == "00:00:59.90")
    }

    /// N-08: a notification names no round; the cloud notifies about the live
    /// one, the last seeded.
    @Test func aNotificationLandsOnTheSeededRound() {
        #expect(ScheduleView.focusIndex([heat("prelims"), heat("final")], event: "15", heat: "1") == 1)
        #expect(ScheduleView.focusIndex([heat("prelims"), heat("final", lanes: [])], event: "15", heat: "1") == 0)
        #expect(ScheduleView.focusIndex([heat("")], event: "9", heat: "1") == nil)
    }

    @Test func theScheduleAsksForEveryRound() async throws {
        let stub = StubServer()
        stub.route("/meet/m1/schedule", json: #"{"heats":[]}"#)
        stub.route("/schedule.json", json: #"{"heats":[]}"#)
        let api = SplouchAPI(address: stub.address, session: stub.session)
        _ = try await api.schedule(meetID: "m1")
        _ = try await api.piSchedule()
        #expect(stub.requests.map { $0.url?.query } == ["rounds=1", "rounds=1"])
    }

    /// S-25: a finals heat names its age group; an unseeded round says so.
    @Test func aHeatCarriesItsAgeGroupAndWhetherItIsSeeded() {
        let heats = Schedule(
            json: json(
                #"{"heats":[{"event":15,"heat":2,"age":"13-14","seeded":false,"lanes":[]},{"event":3,"heat":1,"lanes":[]}]}"#
            )
        ).heats
        #expect(heats.map(\.age) == ["13-14", ""])
        #expect(heats.map(\.seeded) == [false, true])  // an older server: seeded
        #expect(ScheduleView.heading("100 Free", age: "13-14") == "100 Free · 13-14")
        #expect(ScheduleView.heading("100 Free", age: "") == "100 Free")
        #expect(ScheduleView.heading("", age: "17+") == "17+")
    }
}
