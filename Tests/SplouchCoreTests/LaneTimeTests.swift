import Foundation
import Testing

@testable import SplouchCore

/// S-22 and S-23: which of a lane's three times its cell shows, and what an
/// official heat shows while it gives its gaps to the seed.
@Suite struct LaneTimeTests {
    func lane(
        seed: String = "00:00:31.00", console: String = "", result: String = "", status: String = "",
        delta: Double? = nil, better: Bool? = nil
    ) -> ScheduleLane {
        ScheduleLane(
            lane: 3, name: "N", club: "C", seedTime: seed, swimmers: [], consoleTime: console,
            resultTime: result, resultStatus: status, resultDeltaSeconds: delta, resultDeltaBetter: better)
    }

    @Test func theBestKnownTimeWins() {
        #expect(LaneTime.of(lane()) == LaneTime(text: "00:31.00", kind: .seed, spokenKey: "time_seed"))
        #expect(LaneTime.of(lane(console: "00:00:30.15"))?.kind == .console)
        #expect(
            LaneTime.of(lane(console: "00:00:30.15", result: "00:00:30.12"))
                == LaneTime(text: "00:30.12", kind: .official, spokenKey: "time_official"))
        #expect(
            LaneTime.of(lane(console: "00:00:30.15", result: "00:00:30.80", status: "DSQ"))
                == LaneTime(text: "DSQ", kind: .official, spokenKey: "status_dsq", speaksText: false))
        #expect(LaneTime.of(lane(seed: "")) == nil)
    }

    @Test func theHoursGoWhenThereAreNone() {
        #expect(LaneTime.display("00:01:02.34") == "01:02.34")
        #expect(LaneTime.display("01:01:00.00") == "01:01:00.00")
        #expect(LaneTime.display("1:02.34") == "1:02.34")  // a Hytek seed, as written
    }

    @Test func aConsoleTimeIsReadIntoWireForm() {
        #expect(LaneTime.wire("58.21") == "00:00:58.21")
        #expect(LaneTime.wire("1:02.34") == "00:01:02.34")
        #expect(LaneTime.wire("") == "")
        #expect(LaneTime.wire("NT") == "")
    }

    @Test func theGapToTheSeed() {
        let faster = LaneTime.of(lane(result: "00:00:30.12", delta: -0.88, better: true), diff: true)
        #expect(faster == LaneTime(text: "-0.88", kind: .better, spokenKey: "seed_diff"))
        #expect(LaneTime.of(lane(result: "00:00:31.50", delta: 0.5, better: false), diff: true)?.kind == .worse)
        // A disqualified swim shows what the console read.
        let dsq = LaneTime.of(lane(console: "00:00:30.15", status: "DSQ"), diff: true)
        #expect(dsq == LaneTime(text: "00:30.15", kind: .console, spokenKey: "time_console"))
        // No seed, no gap.
        #expect(LaneTime.of(lane(seed: "", result: "00:00:30.12"), diff: true)?.text == "NT")
    }

    @Test func theConsoleTimesGapBeforeTheResult() {
        #expect(
            LaneTime.of(lane(console: "00:00:30.15"), diff: true)
                == LaneTime(text: "-0.85", kind: .better, spokenKey: "seed_diff"))
        #expect(LaneTime.of(lane(seed: "30.15", console: "00:00:31.40"), diff: true)?.text == "+1.25")
        #expect(LaneTime.of(lane(console: "00:00:31.00"), diff: true)?.kind == .worse)  // the server's rule
        #expect(LaneTime.of(lane(seed: "", console: "00:00:30.15"), diff: true)?.text == "NT")
    }

    @Test func aTimeIsReadInHundredths() {
        #expect(LaneTime.hundredths("00:01:02.34") == 6234)
        #expect(LaneTime.hundredths("1:02.34") == 6234)
        #expect(LaneTime.hundredths("58.21") == 5821)
        #expect(LaneTime.hundredths("01:00:00.00") == 360_000)
        #expect(LaneTime.hundredths("") == nil)
        #expect(LaneTime.hundredths("NT") == nil)
        #expect(LaneTime.hundredths("00:00:00.00") == nil)
    }

    @Test func whichHeatsSwap() {
        #expect(LaneTime.swaps(official: true, lanes: [lane()]))
        #expect(LaneTime.swaps(official: false, lanes: [lane(), lane(console: "00:00:30.15")]))
        #expect(!LaneTime.swaps(official: false, lanes: [lane()]))
    }

    @Test func aResultsFramePatchesItsHeatsConsoleTimes() throws {
        var s = try Schedule(
            data: Data(
                #"{"heats":[{"event":1,"heat":2,"lanes":[{"lane":3,"name":"N","seed_time":""}]}]}"#.utf8))
        s.applyConsoleTimes(
            ResultsSnapshot(
                event: "1", heat: "2", eventName: "", eventNameParts: nil, sort: nil,
                lanes: [
                    ResultLane(
                        channel: 3, place: "1", placeInt: 1, time: "30.15", name: "N", club: "", alt: "",
                        deltaSeconds: nil, deltaBetter: nil)
                ]))
        #expect(s.heats[0].lanes[0].consoleTime == "00:00:30.15")
    }

    @Test func theNewFieldsDecodeAndDefault() throws {
        let s = try Schedule(
            data: Data(
                #"{"heats":[{"event":1,"heat":1,"official":true,"lanes":[{"lane":3,"name":"N","seed_time":"00:00:31.00","console_time":"00:00:30.15","result_time":"00:00:30.12","result_status":"","result_delta_seconds":-0.88,"result_delta_better":true}]},{"event":1,"heat":2,"lanes":[{"lane":1,"name":"M"}]}]}"#
                    .utf8))
        #expect(s.heats[0].official)
        #expect(s.heats[0].lanes[0].resultTime == "00:00:30.12")
        #expect(s.heats[0].lanes[0].resultDeltaSeconds == -0.88)
        #expect(s.heats[0].lanes[0].resultDeltaBetter == true)
        // An older server sends none of them.
        #expect(!s.heats[1].official)
        #expect(s.heats[1].lanes[0].consoleTime == "")
        #expect(s.heats[1].lanes[0].resultDeltaSeconds == nil)
    }
}
