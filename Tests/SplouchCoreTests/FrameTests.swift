import Testing
@testable import SplouchCore

@Suite struct FrameTests {
    @Test func decodesEnvelopeWithObjectData() throws {
        let f = try Frame.decode(#"{"event":"meet_live","data":{"live":true}}"#)
        #expect(f.event == "meet_live")
        #expect(f.data["live"]?.bool == true)
    }

    @Test func decodesEnvelopeWithoutData() throws {
        let f = try Frame.decode(#"{"event":"pong"}"#)
        #expect(f == Frame(event: "pong"))
        #expect(try Frame.decode(#"{"event":"schedule_update","data":null}"#).data == .null)
    }

    @Test func decodesBareStringData() throws {
        let f = try Frame.decode(#"{"event":"output","data":"hello"}"#)
        #expect(f.data == .string("hello"))
    }

    @Test func rejectsFrameWithoutEvent() {
        #expect(throws: (any Error).self) { try Frame.decode(#"{"data":{}}"#) }
        #expect(throws: (any Error).self) { try Frame.decode("not json") }
    }

    @Test func pingEncodesWithoutDataKey() throws {
        #expect(try Frame.ping.encoded() == #"{"event":"ping"}"#)
    }

    @Test func joinMeetCarriesMeetIDAndVid() throws {
        let f = Frame.joinMeet(meetID: "aBc123", vid: "0f1e")
        let round = try Frame.decode(try f.encoded())
        #expect(round.event == "join_meet")
        #expect(round.data["meet_id"]?.string == "aBc123")
        #expect(round.data["vid"]?.string == "0f1e")
    }

    @Test func joinMeetOmitsVidWhenAbsent() throws {
        let round = try Frame.decode(try Frame.joinMeet(meetID: "m", vid: nil).encoded())
        #expect(round.data["vid"] == nil)
        #expect(round.data["meet_id"]?.string == "m")
    }

    @Test func numbersReadAsTextEitherWay() throws {
        let v = try JSONValue.parse(#"{"a":"3","b":3,"c":3.5,"d":true,"e":null}"#.data(using: .utf8)!)
        #expect(v["a"]?.text == "3")
        #expect(v["b"]?.text == "3")
        #expect(v["b"]?.int == 3)
        #expect(v["c"]?.text == "3.5")
        #expect(v["c"]?.int == nil)
        #expect(v["e"]?.isNull == true)
        #expect(v["e"]?.text == nil)
    }
}
