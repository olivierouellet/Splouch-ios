import Foundation
import Testing
@testable import SplouchCore

@Suite struct PayloadTests {
    func json(_ s: String) -> JSONValue { try! JSONValue.parse(s.data(using: .utf8)!) }

    @Test func serverInfoDecodes() throws {
        let info = try JSONDecoder().decode(ServerInfo.self, from: #"{"kind":"pi","name":"Piscine","contract":{"api":"v2","app":"v1"}}"#.data(using: .utf8)!)
        #expect(info.kind == .pi)
        #expect(info.name == "Piscine")
        #expect(info.contract == ServerInfo.expectedContract)
    }

    @Test func serverInfoRejectsUnknownKind() {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(ServerInfo.self, from: #"{"kind":"tv","name":"x","contract":{"api":"v2","app":"v1"}}"#.data(using: .utf8)!)
        }
    }

    @Test func meetListReadsFlagsAndDefaults() throws {
        let list = try MeetList(json: json(#"{"meets":[{"id":"aBc","name":"Open","offline":true},{"id":"d","meet_date":"2026-09-12","has_picker_image":true}]}"#))
        #expect(list.meets.count == 2)
        #expect(list.meets[0].offline == true)
        #expect(list.meets[0].location == "")
        #expect(list.meets[1].hasPickerImage == true)
        #expect(list.meets[1].meetDate == "2026-09-12")
    }

    @Test func meetWithoutIDIsAnError() {
        #expect(throws: PayloadError.self) { try MeetList(json: json(#"{"meets":[{"name":"x"}]}"#)) }
    }

    @Test func pickerConfigReadsStrings() {
        let c = PickerConfig(json: json(#"{"title":"Splouch","has_logo":true,"logo_above":false,"lang":"fr","analytics_enabled":true,"strings":{"no_meets":"Aucune","privacy_note":"p"}}"#))
        #expect(c.title == "Splouch")
        #expect(c.hasLogo)
        #expect(c.lang == "fr")
        #expect(c.analyticsEnabled)
        #expect(c.strings["no_meets"] == "Aucune")
    }

    @Test func meetConfigAndSettings() {
        let c = MeetConfig(json: json(#"""
        {"name":"Open","location":"Pool","sport":"Swimming","meet_date":"2026-09-12","live":true,
         "settings":{"num_lanes":6,"show_club":false,"show_delta_header":false,
                     "theme_colors":{"bg":"#000"},"theme_fonts":{"family":"Orbitron"},
                     "locale":"fr","labels":{"event":"ÉP","heat":"SÉR"},"label_style":"short"}}
        """#))
        #expect(c.live)
        #expect(c.settings.numLanes == 6)
        #expect(c.settings.showClub == false)
        #expect(c.settings.showName == true)
        #expect(c.settings.showDeltaHeader == false)
        #expect(c.settings.themeColors["bg"] == "#000")
        #expect(c.settings.themeFonts["family"] == "Orbitron")
        #expect(c.settings.locale == "fr")
        #expect(c.settings.labels["event"] == "ÉP")
        #expect(c.settings.labelStyle == "short")
    }

    @Test func settingsDefaultsWhenEmpty() {
        let s = MeetSettings(json: .object([:]))
        #expect(s == MeetSettings())
        #expect(s.numLanes == 8)
        #expect(s.labelStyle == nil)
        // A-11: a server too old to send `console` is a server with a console.
        #expect(s.console == ConsoleInfo(key: "", timed: true))
    }

    // A-11 / api.md §5.4: `timed` is the whole question and `key` is diagnostic.
    @Test func consoleIsReadForItsTimedFlagAndNeverItsKey() {
        let manual = MeetSettings(json: json(#"{"console":{"key":"manual","timed":false}}"#))
        #expect(manual.console.timed == false)
        #expect(manual.console.key == "manual")

        let cts = MeetSettings(json: json(#"{"console":{"key":"cts_gen6","timed":true}}"#))
        #expect(cts.console.timed)

        // A local plugin driven by hand: an unknown key, and no times. A client
        // matching on `key == "manual"` would call this one timed.
        let plugin = MeetSettings(json: json(#"{"console":{"key":"clubhouse_buttons","timed":false}}"#))
        #expect(plugin.console.timed == false)

        // A plugin that does time, whose key this app has never heard of.
        let timedPlugin = MeetSettings(json: json(#"{"console":{"key":"ares21","timed":true}}"#))
        #expect(timedPlugin.console.timed)
    }

    // Anything short of a clear "false" shows the tab, rather than removing it
    // on a guess: absent, null, not an object, or a `timed` of the wrong type.
    @Test func malformedConsoleDefaultsToTimed() {
        #expect(MeetSettings(json: json(#"{}"#)).console.timed)
        #expect(MeetSettings(json: json(#"{"console":null}"#)).console.timed)
        #expect(MeetSettings(json: json(#"{"console":"manual"}"#)).console.timed)
        #expect(MeetSettings(json: json(#"{"console":[]}"#)).console.timed)
        #expect(MeetSettings(json: json(#"{"console":{}}"#)).console.timed)
        #expect(MeetSettings(json: json(#"{"console":{"key":"manual"}}"#)).console.timed)
        #expect(MeetSettings(json: json(#"{"console":{"timed":"false"}}"#)).console.timed)
        #expect(MeetSettings(json: json(#"{"console":{"timed":0}}"#)).console.timed)
    }

    @Test func piDisplayConfigReadsTopLevelSettings() {
        let c = PiDisplayConfig(json: json(#"{"num_lanes":10,"meet_title":"Regional","locale":"es","display_strings":{"waiting_server":"…"},"labels":{"lane":"CL"}}"#))
        #expect(c.meetTitle == "Regional")
        #expect(c.locale == "es")
        #expect(c.settings.numLanes == 10)
        #expect(c.settings.labels["lane"] == "CL")
        #expect(c.displayStrings["waiting_server"] == "…")
        // A-11 on a Pi: `console` sits at the top level beside the rest (§6.1).
        #expect(c.settings.console.timed)
        let manual = PiDisplayConfig(json: json(#"{"meet_title":"Time trial","console":{"key":"manual","timed":false}}"#))
        #expect(manual.settings.console.timed == false)
    }

    @Test func resultsSnapshotReadsSortAndLanes() {
        let r = ResultsSnapshot(json: json(#"{"event":3,"heat":"1","event_name":"x","sort":"place","lanes":[{"channel":4,"place":"1","place_int":1,"time":"2:20.92","name":"N","club":"C","alt":"","delta":"<span>","delta_seconds":-0.46,"delta_better":true}]}"#))
        #expect(r.event == "3")
        #expect(r.heat == "1")
        #expect(r.sort == .place)
        #expect(r.lanes[0].channel == 4)
        #expect(r.lanes[0].placeInt == 1)
        #expect(r.lanes[0].deltaSeconds == -0.46)
        #expect(r.lanes[0].deltaBetter == true)
    }

    @Test func resultsSnapshotSortAbsentIsNil() {
        let r = ResultsSnapshot(json: json(#"{"event":"3","heat":"1","lanes":[]}"#))
        #expect(r.sort == nil)
        #expect(ResultsSnapshot(json: json(#"{"sort":"weird","lanes":[]}"#)).sort == nil)
    }

    @Test func scheduleReadsHeatsLanesAndSwimmers() {
        let s = Schedule(json: json(#"{"heats":[{"event":3,"heat":1,"event_name":"200 Free","time":"10:42","lanes":[{"lane":4,"name":"Relay A","club":"C","seed_time":"1:50.00","swimmers":[{"pos":1,"name":"Doe, Jane","first":"Jane"}]}]},{"event":3,"heat":2,"lanes":[]}]}"#))
        #expect(s.heats.count == 2)
        #expect(s.heats[0].event == "3")
        #expect(s.heats[0].heat == "1")
        #expect(s.heats[0].lanes[0].lane == 4)
        #expect(s.heats[0].lanes[0].seedTime == "1:50.00")
        #expect(s.heats[0].lanes[0].swimmers[0].first == "Jane")
        #expect(s.heats[1].lanes.isEmpty)
    }

    @Test func nextHeatsReads() {
        let n = NextHeats(json: json(#"{"heats":[{"event":3,"heat":1,"event_name":"x","time":"10:42","swimmers":[{"lane":1,"name":"a","club":"b","alt":""}]}]}"#))
        #expect(n.heats[0].event == "3")
        #expect(n.heats[0].swimmers[0].lane == 1)
    }

    @Test func i18nBundleReads() {
        let b = I18nBundle(json: json(#"{"lang":"fr","mobile":{"scoreboard":"Tableau"},"display":{"retrying":"r"},"labels":{"short":{"event":"ÉP"},"long":{"event":"ÉPREUVE"}},"event_name":{"unit":"m","separator":"  —  "}}"#))
        #expect(b.lang == "fr")
        #expect(b.mobile["scoreboard"] == "Tableau")
        #expect(b.labels["long"]?["event"] == "ÉPREUVE")
        #expect(b.eventName["unit"] == "m")
    }

    @Test func directoryAndLocalesDecode() throws {
        let d = try JSONDecoder().decode(ServerDirectory.self, from: #"{"servers":[{"name":"Splouch","url":"https://splouch.app","kind":"cloud"}]}"#.data(using: .utf8)!)
        #expect(d.servers[0].url == "https://splouch.app")
        let l = try JSONDecoder().decode([LocaleEntry].self, from: #"[{"code":"fr","name":"Français"}]"#.data(using: .utf8)!)
        #expect(l[0].code == "fr")
    }

    @Test func meetLive() {
        #expect(MeetLive(json: json(#"{"live":true}"#)).live)
        #expect(MeetLive(json: .object([:])).live == false)
    }
}
