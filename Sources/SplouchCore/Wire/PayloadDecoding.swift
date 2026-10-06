import Foundation

// Lenient readers over JSONValue. Each mirrors how the reference page reads the
// same payload: absent strings are "", absent flags take their documented
// default, numbers may arrive as strings.

extension JSONValue {
    func str(_ key: String) -> String { self[key]?.text ?? "" }
    func flag(_ key: String, default d: Bool) -> Bool { self[key]?.bool ?? d }
    func integer(_ key: String) -> Int? {
        if let i = self[key]?.int { return i }
        if let s = self[key]?.string { return Int(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }
    func strings(_ key: String) -> [String: String] {
        guard let o = self[key]?.object else { return [:] }
        return o.compactMapValues(\.text)
    }
    func list(_ key: String) -> [JSONValue] { self[key]?.array ?? [] }
}

public struct PayloadError: Error, Sendable, Equatable {
    public var message: String
    public init(_ message: String) { self.message = message }
}

extension JSONValue {
    public static func parse(_ data: Data) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: data)
    }
}

extension MeetSummary {
    public init(json: JSONValue) throws {
        guard let id = json["id"]?.text, !id.isEmpty else { throw PayloadError("meet without id") }
        self.init(
            id: id, name: json.str("name"), location: json.str("location"),
            sport: json.str("sport"), organizer: json.str("organizer"),
            meetDate: json.str("meet_date"), offline: json.flag("offline", default: false),
            hasPickerImage: json.flag("has_picker_image", default: false),
            country: json.str("country"), province: json.str("province"),
            base: ServerAddress(base: json.str("base")))
    }
}

extension MeetList {
    public init(json: JSONValue) throws {
        meets = try json.list("meets").map(MeetSummary.init(json:))
    }
    public init(data: Data) throws { try self.init(json: JSONValue.parse(data)) }
}

extension PickerConfig {
    public init(json: JSONValue) {
        title = json.str("title")
        windowTitle = json.str("window_title")
        hasLogo = json.flag("has_logo", default: false)
        logoAbove = json.flag("logo_above", default: false)
        lang = json.str("lang")
        analyticsEnabled = json.flag("analytics_enabled", default: false)
        strings = json.strings("strings")
    }
    public init(data: Data) throws { self.init(json: try JSONValue.parse(data)) }
}

extension MeetSettings {
    public init(json: JSONValue) {
        self.init(
            numLanes: json.integer("num_lanes") ?? 8,
            showName: json.flag("show_name", default: true),
            showClub: json.flag("show_club", default: true),
            showDelta: json.flag("show_delta", default: true),
            showPosition: json.flag("show_position", default: true),
            showPodium: json.flag("show_podium", default: true),
            showLaneHeader: json.flag("show_lane_header", default: true),
            showNameHeader: json.flag("show_name_header", default: true),
            showClubHeader: json.flag("show_club_header", default: true),
            showTimeHeader: json.flag("show_time_header", default: true),
            showDeltaHeader: json.flag("show_delta_header", default: true),
            showPositionHeader: json.flag("show_position_header", default: true),
            showLaps: json.flag("show_laps", default: false),
            lapDirection: json["lap_direction"]?.text ?? "up",
            themeColors: json.strings("theme_colors"),
            themeFonts: json.strings("theme_fonts"),
            locale: json["locale"]?.text ?? "en",
            labels: json.strings("labels"),
            labelStyle: json["label_style"]?.string,
            console: ConsoleInfo(json: json["console"])
        )
    }
}

extension ConsoleInfo {
    /// A-11 defaults to a console that times, and every way the field can fail
    /// to say otherwise lands there: absent (a server older than the field),
    /// `null`, or anything that is not an object. `timed` itself is read with
    /// the same default, so a malformed value — `"false"`, `0` — shows the tab
    /// rather than removing it on a guess.
    public init(json: JSONValue?) {
        guard let json, json.object != nil else {
            self.init()
            return
        }
        self.init(key: json.str("key"), timed: json.flag("timed", default: true))
    }
}

extension MeetConfig {
    public init(json: JSONValue) {
        name = json.str("name")
        location = json.str("location")
        sport = json.str("sport")
        appWindowTitle = json.str("app_window_title")
        meetDate = json.str("meet_date")
        live = json.flag("live", default: false)
        base = ServerAddress(base: json.str("base"))
        settings = MeetSettings(json: json["settings"] ?? .object([:]))
    }
    public init(data: Data) throws { self.init(json: try JSONValue.parse(data)) }
}

extension PiDisplayConfig {
    public init(json: JSONValue) {
        meetTitle = json.str("meet_title")
        locale = json["locale"]?.text ?? "en"
        displayStrings = json.strings("display_strings")
        settings = MeetSettings(json: json)
    }
    public init(data: Data) throws { self.init(json: try JSONValue.parse(data)) }
}

extension EventNameParts {
    /// nil for `null` or anything that is not an object — the field is optional.
    public init?(json: JSONValue?) {
        guard let json, json.object != nil else { return nil }
        self.init(
            raw: json.str("raw"), dist: json.str("dist"), stroke: json.str("stroke"),
            relay: json.flag("relay", default: false), gender: json.str("gender"),
            age: json.str("age"), ageKey: json.str("age_key"), round: json.str("round"))
    }
}

extension ResultLane {
    public init(json: JSONValue) {
        channel = json.integer("channel") ?? 0
        place = json.str("place")
        placeInt = json.integer("place_int")
        time = json.str("time")
        name = json.str("name")
        club = json.str("club")
        alt = json.str("alt")
        deltaSeconds = json["delta_seconds"]?.double
        deltaBetter = json["delta_better"]?.bool
    }
}

extension ResultsSnapshot {
    public init(json: JSONValue) {
        event = json.str("event")
        heat = json.str("heat")
        eventName = json.str("event_name")
        eventNameParts = EventNameParts(json: json["event_name_parts"])
        sort = json["sort"]?.string.flatMap(ResultsSort.init(rawValue:))
        lanes = json.list("lanes").map(ResultLane.init(json:))
    }
}

extension NextHeats {
    public init(json: JSONValue) {
        heats = json.list("heats").map { h in
            NextHeat(
                event: h.str("event"), heat: h.str("heat"), eventName: h.str("event_name"),
                eventNameParts: EventNameParts(json: h["event_name_parts"]), time: h.str("time"),
                swimmers: h.list("swimmers").map { s in
                    NextHeatSwimmer(
                        lane: s.integer("lane") ?? 0, name: s.str("name"),
                        club: s.str("club"), alt: s.str("alt"))
                })
        }
    }
}

extension Schedule {
    public init(json: JSONValue) {
        heats = json.list("heats").map { h in
            ScheduleHeat(
                event: h.str("event"), heat: h.str("heat"), eventName: h.str("event_name"),
                eventNameParts: EventNameParts(json: h["event_name_parts"]), time: h.str("time"),
                lanes: h.list("lanes").map { l in
                    ScheduleLane(
                        lane: l.integer("lane") ?? 0, name: l.str("name"), club: l.str("club"),
                        seedTime: l.str("seed_time"),
                        swimmers: l.list("swimmers").map { s in
                            ScheduleSwimmer(name: s.str("name"), first: s.str("first"))
                        },
                        consoleTime: l.str("console_time"), resultTime: l.str("result_time"),
                        resultStatus: l.str("result_status"),
                        resultDeltaSeconds: l["result_delta_seconds"]?.double,
                        resultDeltaBetter: l["result_delta_better"]?.bool)
                },
                official: h.flag("official", default: false))
        }
    }
    public init(data: Data) throws { self.init(json: try JSONValue.parse(data)) }
}

extension I18nBundle {
    public init(json: JSONValue) {
        var labels: [String: [String: String]] = [:]
        if let l = json["labels"]?.object {
            for (style, table) in l {
                if let t = table.object { labels[style] = t.compactMapValues(\.text) }
            }
        }
        self.init(
            lang: json.str("lang"), mobile: json.strings("mobile"),
            labels: labels, eventName: json.strings("event_name"))
    }
    public init(data: Data) throws { self.init(json: try JSONValue.parse(data)) }
}

extension MeetLive {
    public init(json: JSONValue) { live = json.flag("live", default: false) }
}
