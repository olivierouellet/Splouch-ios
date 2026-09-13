import Testing
@testable import SplouchCore

@Suite struct ScoreboardStateTests {
    let t0 = ContinuousClock.now

    func frame(_ json: String) -> JSONValue {
        try! JSONValue.parse(json.data(using: .utf8)!)
    }

    /// A board that has connected and been told the meet is live.
    func liveBoard(lanes: Int = 4) -> ScoreboardState {
        var s = ScoreboardState(numLanes: lanes)
        s.socketConnected()
        s.setMeetLive(true)
        return s
    }

    // L-04, L-09

    @Test func alwaysHasNumLanesRows() {
        let s = ScoreboardState(numLanes: 6)
        #expect(s.lanes.count == 6)
        #expect(s.lanes.allSatisfy { $0 == LaneRow() })
    }

    // L-10

    @Test func framesMergeIntoExistingState() {
        var s = liveBoard()
        s.apply(frame(#"{"current_event":"3","current_heat":"1","lane_name1":"A","lane_club1":"X"}"#), at: t0)
        s.apply(frame(#"{"lane_time1":"25.61"}"#), at: t0)
        #expect(s[lane: 1].name == "A")
        #expect(s[lane: 1].club == "X")
        #expect(s[lane: 1].time == "25.61")
        #expect(s.currentEvent == "3")
        #expect(s.currentHeat == "1")
    }

    @Test func unknownKeysAndNonObjectsAreIgnored() {
        var s = liveBoard()
        let before = s
        s.apply(frame(#"{"something_new":1,"lane_delta1":"<span>+0.1</span>","lane_splits1":3}"#), at: t0)
        #expect(s == before)
        s.apply(.string("nope"), at: t0)
        #expect(s == before)
    }

    @Test func structuredDeltaIsReadAndNullClears() {
        var s = liveBoard()
        s.apply(frame(#"{"lane_delta_seconds1":-0.46,"lane_delta_better1":true}"#), at: t0)
        #expect(s[lane: 1].deltaSeconds == -0.46)
        #expect(s[lane: 1].deltaBetter == true)
        s.apply(frame(#"{"lane_delta_seconds1":null,"lane_delta_better1":null}"#), at: t0)
        #expect(s[lane: 1].deltaSeconds == nil)
        #expect(s[lane: 1].deltaBetter == nil)
    }

    @Test func placeIsTrimmedSoBlankMeansNoPlace() {
        var s = liveBoard()
        s.apply(frame(#"{"lane_place1":" ","lane_place2":"1"}"#), at: t0)
        #expect(s[lane: 1].place == "")
        #expect(s[lane: 2].place == "1")
    }

    @Test func headerFieldsAndPartsAreRead() {
        var s = liveBoard()
        s.apply(frame(#"{"event_name":"200 m dos","event_name_parts":{"raw":"200 Backstroke","dist":"200","stroke":"backstroke","relay":false,"gender":"girls","age":"< 12","age_key":""},"heat_time":"10:42","expected_splits":4}"#), at: t0)
        #expect(s.eventName == "200 m dos")
        #expect(s.eventNameParts?.stroke == "backstroke")
        #expect(s.heatTime == "10:42")
        #expect(s.expectedSplits == 4)
        s.apply(frame(#"{"event_name_parts":null}"#), at: t0)
        #expect(s.eventNameParts == nil)
    }

    // L-11

    @Test func runningEdgeStylesTheCellAndStopEdgeLocksOnce() {
        var s = liveBoard()
        s.apply(frame(#"{"lane_running1":true,"running_time":"10.00"}"#), at: t0)
        #expect(s[lane: 1].timeStyle == .running)
        s.apply(frame(#"{"lane_running1":false,"lane_time1":"25.61","running_time":"25.61"}"#), at: t0 + .seconds(1))
        #expect(s[lane: 1].timeStyle == .locked(generation: 1))
        #expect(s[lane: 1].time == "25.61")
        // A second finish plays the transition again.
        s.apply(frame(#"{"lane_running1":true,"running_time":"30.00"}"#), at: t0 + .seconds(2))
        s.apply(frame(#"{"lane_running1":false,"lane_time1":"50.00","running_time":"50.00"}"#), at: t0 + .seconds(3))
        #expect(s[lane: 1].timeStyle == .locked(generation: 2))
    }

    @Test func lockIsCancelledWhenTheLaneRunsAgain() {
        var s = liveBoard()
        s.apply(frame(#"{"lane_running1":true,"running_time":"10.00"}"#), at: t0)
        s.apply(frame(#"{"lane_running1":false,"running_time":"25.00"}"#), at: t0)
        s.apply(frame(#"{"lane_running1":true,"running_time":"25.00"}"#), at: t0)
        #expect(s[lane: 1].timeStyle == .running)
    }

    @Test func aFalseFlagWithoutAnEdgeDoesNotLock() {
        var s = liveBoard()
        s.apply(frame(#"{"lane_running1":false,"lane_time1":"25.61"}"#), at: t0)
        #expect(s[lane: 1].timeStyle == .plain)
    }

    // L-12

    @Test func runningLanesShowTheOneRaceClock() {
        var s = liveBoard()
        s.apply(frame(#"{"lane_running1":true,"lane_running2":true,"lane_running3":false,"lane_time3":"","running_time":"12.30"}"#), at: t0)
        #expect(s[lane: 1].time == "12.3")
        #expect(s[lane: 2].time == "12.3")
        #expect(s[lane: 3].time == "")
        s.tick(at: t0 + .milliseconds(1_500))
        #expect(s[lane: 1].time == "13.8")
        #expect(s[lane: 2].time == "13.8")
        #expect(s[lane: 3].time == "")
        #expect(s[lane: 1].pulse == false)
    }

    @Test func aSplitFreezesTheLaneNotTheClock() {
        var s = liveBoard()
        s.apply(frame(#"{"lane_running1":true,"lane_running2":true,"running_time":"10.00"}"#), at: t0)
        s.apply(frame(#"{"lane_running1":false,"lane_time1":"25.61","running_time":"25.61"}"#), at: t0 + .seconds(15))
        s.tick(at: t0 + .seconds(16))
        #expect(s[lane: 1].time == "25.61")
        #expect(s[lane: 2].time == "26.6")
    }

    @Test func laneEdgeAloneNeverStartsOrResetsTheClock() {
        var s = liveBoard()
        s.apply(frame(#"{"lane_running1":true}"#), at: t0)
        #expect(!s.clock.isRunning)
        #expect(s[lane: 1].time == "")
        #expect(s[lane: 1].pulse == true)
        s.apply(frame(#"{"running_time":"40.00"}"#), at: t0)
        #expect(s[lane: 1].time == "40.0")
        // A lane starting later joins the same clock; it does not restart it.
        s.apply(frame(#"{"lane_running2":true}"#), at: t0 + .seconds(2))
        s.tick(at: t0 + .seconds(2))
        #expect(s[lane: 2].time == "42.0")
        #expect(s[lane: 1].time == "42.0")
    }

    @Test func splitInTheSameFrameAsARebaseDoesNotOverpaintTheClock() {
        var s = liveBoard()
        s.apply(frame(#"{"lane_running1":true,"lane_time1":"25.61","running_time":"30.00"}"#), at: t0)
        #expect(s[lane: 1].time == "30.0")
    }

    @Test func joinedMidHeatPulsesUntilTheFirstRebase() {
        var s = liveBoard()
        s.apply(frame(#"{"lane_running1":true,"lane_time1":"25.61"}"#), at: t0)
        #expect(s[lane: 1].time == "25.61")
        #expect(s[lane: 1].pulse == true)
        s.apply(frame(#"{"running_time":"40.00"}"#), at: t0)
        #expect(s[lane: 1].pulse == false)
    }

    @Test func silenceFreezesForwardAndFallsBackToThePulse() {
        var s = liveBoard()
        s.apply(frame(#"{"lane_running1":true,"running_time":"10.00"}"#), at: t0)
        s.tick(at: t0 + .seconds(5))
        #expect(s[lane: 1].time == "15.0")
        #expect(s[lane: 1].pulse == false)
        s.tick(at: t0 + .seconds(7))
        #expect(s[lane: 1].time == "16.0")
        #expect(!s.clock.isRunning)
        #expect(s[lane: 1].pulse == true)
        s.tick(at: t0 + .seconds(20))
        #expect(s[lane: 1].time == "16.0")
        // The next re-base starts it again.
        s.apply(frame(#"{"running_time":"30.00"}"#), at: t0 + .seconds(21))
        #expect(s[lane: 1].time == "30.0")
        #expect(s[lane: 1].pulse == false)
    }

    @Test func suspendStopsTheTickerAndDoesNotResumeFromAStaleBase() {
        var s = liveBoard()
        s.apply(frame(#"{"lane_running1":true,"running_time":"10.00"}"#), at: t0)
        s.suspend()
        #expect(!s.clock.isRunning)
        #expect(s[lane: 1].pulse == true)
        s.tick(at: t0 + .seconds(120))
        #expect(s[lane: 1].time == "10.0")
        s.apply(frame(#"{"running_time":"2:10.00"}"#), at: t0 + .seconds(121))
        #expect(s[lane: 1].time == "2:10.0")
    }

    @Test func meetLiveFalseStopsEveryClockAndPulse() {
        var s = liveBoard()
        s.apply(frame(#"{"lane_running1":true,"running_time":"10.00"}"#), at: t0)
        s.setMeetLive(false)
        #expect(!s.clock.isRunning)
        #expect(s[lane: 1].pulse == false)
        #expect(s[lane: 1].time == "10.0")
        #expect(s[lane: 1].running == true)
    }

    @Test func disconnectImpliesNotLive() {
        var s = liveBoard()
        s.apply(frame(#"{"lane_running1":true,"running_time":"10.00"}"#), at: t0)
        s.socketDisconnected()
        #expect(s.meetLive == false)
        #expect(s.connected == false)
        #expect(!s.clock.isRunning)
        #expect(s[lane: 1].pulse == false)
        #expect(s[lane: 1].time == "10.0")
    }

    @Test func noPulseWhileNotLiveEvenWithRunningLanes() {
        var s = ScoreboardState(numLanes: 2)
        s.socketConnected()
        s.apply(frame(#"{"lane_running1":true}"#), at: t0)
        #expect(s[lane: 1].pulse == false)
        s.setMeetLive(true)
        #expect(s[lane: 1].pulse == true)
    }

    @Test func clockStopsWhenNoLaneIsRunning() {
        var s = liveBoard()
        s.apply(frame(#"{"lane_running1":true,"running_time":"10.00"}"#), at: t0)
        s.apply(frame(#"{"lane_running1":false,"lane_time1":"20.00","running_time":"20.00"}"#), at: t0)
        #expect(!s.clock.isRunning)
        #expect(s[lane: 1].time == "20.00")
    }

    // L-13

    @Test func heatChangeBlanksTimesDeltasAndPlaces() {
        var s = liveBoard()
        s.apply(frame(#"{"current_event":"3","current_heat":"1","lane_name1":"A","lane_time1":"25.61","lane_place1":"1","lane_delta_seconds1":-0.4,"lane_delta_better1":true}"#), at: t0)
        s.apply(frame(#"{"current_heat":"2","lane_name1":"B"}"#), at: t0)
        #expect(s[lane: 1].name == "B")
        #expect(s[lane: 1].time == "")
        #expect(s[lane: 1].place == "")
        #expect(s[lane: 1].deltaSeconds == nil)
        #expect(s[lane: 1].deltaBetter == nil)
        #expect(s[lane: 1].timeStyle == .plain)
        #expect(!s.clock.isRunning)
    }

    @Test func eventChangeBlanksToo() {
        var s = liveBoard()
        s.apply(frame(#"{"current_event":"3","current_heat":"1","lane_time1":"25.61"}"#), at: t0)
        s.apply(frame(#"{"current_event":"4","current_heat":"1"}"#), at: t0)
        #expect(s[lane: 1].time == "")
    }

    @Test func firstFrameAfterConnectIsABaselineNotAChange() {
        var s = liveBoard()
        s.apply(frame(#"{"current_event":"3","current_heat":"1","lane_time1":"25.61","lane_place1":"1"}"#), at: t0)
        #expect(s[lane: 1].time == "25.61")
        #expect(s[lane: 1].place == "1")
        // Same values again: no change, nothing blanks.
        s.apply(frame(#"{"current_event":"3","current_heat":"1"}"#), at: t0)
        #expect(s[lane: 1].time == "25.61")
    }

    @Test func reconnectReplayDoesNotBlankOrFlash() {
        var s = liveBoard()
        s.apply(frame(#"{"current_event":"3","current_heat":"1","lane_running1":true,"running_time":"10.00"}"#), at: t0)
        s.socketDisconnected()
        s.socketConnected()
        s.setMeetLive(true)
        // The server replays its merged snapshot for a later heat.
        s.apply(frame(#"{"current_event":"3","current_heat":"2","lane_running1":false,"lane_time1":"25.61","lane_place1":"1"}"#), at: t0 + .seconds(30))
        #expect(s[lane: 1].time == "25.61")
        #expect(s[lane: 1].place == "1")
        #expect(s[lane: 1].timeStyle != .locked(generation: 2))
    }

    @Test func heatChangeWithLanesStillRunningKeepsThemPulsing() {
        var s = liveBoard()
        s.apply(frame(#"{"current_heat":"1","lane_running1":true,"running_time":"10.00"}"#), at: t0)
        s.apply(frame(#"{"current_heat":"2"}"#), at: t0)
        // Running on the previous frame: the time stays (L-13, second case); the
        // ticker stopped, so the lane pulses until the next re-base.
        #expect(s[lane: 1].time == "10.0")
        #expect(s[lane: 1].running == true)
        #expect(s[lane: 1].pulse == true)
        #expect(s[lane: 1].timeStyle == .running)
    }
}
