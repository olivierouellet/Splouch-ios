import Foundation

// Typed readings of the payloads in api.md §5. Decoding is lenient in the way the
// reference pages are: a missing string is "", a missing flag is its documented
// default, a number that arrives as a string still reads. Nothing here adds a
// field the contract does not name.

/// `GET /server` (api.md §5.10).
public struct ServerInfo: Sendable, Equatable, Decodable {
    public var kind: ServerKind
    public var name: String
    public var contract: Contract

    public struct Contract: Sendable, Equatable, Decodable {
        public var api: String
        public var app: String
        public init(api: String, app: String) { self.api = api; self.app = app }
    }

    public init(kind: ServerKind, name: String, contract: Contract) {
        self.kind = kind; self.name = name; self.contract = contract
    }

    /// The contract versions this client was written against.
    public static let expectedContract = Contract(api: "v2", app: "v1")
}

/// Decides the shape of the session, not just the base URL: a Pi has one meet
/// and no picker, a cloud starts at the meet list.
public enum ServerKind: String, Sendable, Decodable {
    case pi
    case cloud
}

/// One row of `GET /meets` (api.md §5.6).
public struct MeetSummary: Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var location: String
    public var sport: String
    public var organizer: String
    public var meetDate: String
    /// Retained meet with no relay connected — still listed on purpose (P-03).
    public var offline: Bool
    public var hasPickerImage: Bool
}

public struct MeetList: Sendable, Equatable {
    public var meets: [MeetSummary]
}

/// `GET /picker/config` (api.md §5.7).
public struct PickerConfig: Sendable, Equatable {
    public var title: String
    public var windowTitle: String
    public var hasLogo: Bool
    public var logoAbove: Bool
    public var lang: String
    public var analyticsEnabled: Bool
    public var strings: [String: String]
}

/// `GET /meet/{meet_id}/config` (api.md §4, §6.2).
public struct MeetConfig: Sendable, Equatable {
    public var name: String
    public var location: String
    public var sport: String
    public var appWindowTitle: String
    public var meetDate: String
    public var live: Bool
    public var settings: MeetSettings
}

/// The meet's display config — the `settings` block of api.md §5.4, also what a
/// Pi's `GET /config` carries at top level.
public struct MeetSettings: Sendable, Equatable {
    public var numLanes: Int
    public var showName: Bool
    public var showClub: Bool
    public var showDelta: Bool
    public var showPosition: Bool
    public var showPodium: Bool
    public var showLaneHeader: Bool
    public var showNameHeader: Bool
    public var showClubHeader: Bool
    public var showTimeHeader: Bool
    public var showDeltaHeader: Bool
    public var showPositionHeader: Bool
    public var themeColors: [String: String]
    public var themeFonts: [String: String]
    public var locale: String
    /// Resolved for the meet's locale and the operator's style — the default a
    /// client renders before any user preference (T-04).
    public var labels: [String: String]
    /// `"short"` or `"long"`; nil when the server predates the field.
    public var labelStyle: String?

    public init(
        numLanes: Int = 8,
        showName: Bool = true, showClub: Bool = true, showDelta: Bool = true,
        showPosition: Bool = true, showPodium: Bool = true,
        showLaneHeader: Bool = true, showNameHeader: Bool = true, showClubHeader: Bool = true,
        showTimeHeader: Bool = true, showDeltaHeader: Bool = true, showPositionHeader: Bool = true,
        themeColors: [String: String] = [:], themeFonts: [String: String] = [:],
        locale: String = "en", labels: [String: String] = [:],
        labelStyle: String? = nil
    ) {
        self.numLanes = numLanes
        self.showName = showName; self.showClub = showClub; self.showDelta = showDelta
        self.showPosition = showPosition; self.showPodium = showPodium
        self.showLaneHeader = showLaneHeader; self.showNameHeader = showNameHeader
        self.showClubHeader = showClubHeader; self.showTimeHeader = showTimeHeader
        self.showDeltaHeader = showDeltaHeader; self.showPositionHeader = showPositionHeader
        self.themeColors = themeColors; self.themeFonts = themeFonts
        self.locale = locale; self.labels = labels
        self.labelStyle = labelStyle
    }
}

/// A Pi's `GET /config` (api.md §4 local, §6.1): the same display config plus
/// the meet title, locale and the client-rendered status strings.
public struct PiDisplayConfig: Sendable, Equatable {
    public var meetTitle: String
    public var locale: String
    public var displayStrings: [String: String]
    public var settings: MeetSettings
}

/// `event_name_parts` (api.md §5.1): an event name decomposed into keys so a
/// client reading in another language can compose it from `GET /i18n/{lang}`.
public struct EventNameParts: Sendable, Equatable {
    public var raw: String
    public var dist: String
    public var stroke: String
    public var relay: Bool
    public var gender: String
    public var age: String
    public var ageKey: String

    public init(raw: String = "", dist: String = "", stroke: String = "", relay: Bool = false,
                gender: String = "", age: String = "", ageKey: String = "") {
        self.raw = raw; self.dist = dist; self.stroke = stroke; self.relay = relay
        self.gender = gender; self.age = age; self.ageKey = ageKey
    }
}

/// `results_snapshot` (api.md §5.2).
public struct ResultsSnapshot: Sendable, Equatable {
    public var event: String
    public var heat: String
    public var eventName: String
    public var eventNameParts: EventNameParts?
    /// nil when the relay predates the field; R-05 reads that as lane order.
    public var sort: ResultsSort?
    public var lanes: [ResultLane]
}

public enum ResultsSort: String, Sendable, Decodable {
    case lane
    case place
}

public struct ResultLane: Sendable, Equatable {
    public var channel: Int
    public var place: String
    public var placeInt: Int?
    public var time: String
    public var name: String
    public var club: String
    public var alt: String
    public var deltaSeconds: Double?
    public var deltaBetter: Bool?
}

/// `next_heats` (api.md §5.3).
public struct NextHeats: Sendable, Equatable {
    public var heats: [NextHeat]
}

public struct NextHeat: Sendable, Equatable {
    public var event: String
    public var heat: String
    public var eventName: String
    public var eventNameParts: EventNameParts?
    public var time: String
    public var swimmers: [NextHeatSwimmer]
}

public struct NextHeatSwimmer: Sendable, Equatable {
    public var lane: Int
    public var name: String
    public var club: String
    public var alt: String
}

/// `GET /meet/{meet_id}/schedule` (api.md §5.8): the whole start list.
public struct Schedule: Sendable, Equatable {
    public var heats: [ScheduleHeat]
}

public struct ScheduleHeat: Sendable, Equatable {
    public var event: String
    public var heat: String
    public var eventName: String
    public var eventNameParts: EventNameParts?
    public var time: String
    public var lanes: [ScheduleLane]
}

public struct ScheduleLane: Sendable, Equatable {
    public var lane: Int
    public var name: String
    public var club: String
    public var seedTime: String
    public var swimmers: [ScheduleSwimmer]
}

public struct ScheduleSwimmer: Sendable, Equatable {
    public var name: String
    public var first: String
}

/// `GET /i18n/{lang}` (api.md §5.9).
public struct I18nBundle: Sendable, Equatable, Codable {
    public var lang: String
    public var mobile: [String: String]
    public var display: [String: String]
    public var labels: [String: [String: String]]
    public var eventName: [String: String]

    public init(lang: String, mobile: [String: String] = [:], display: [String: String] = [:],
                labels: [String: [String: String]] = [:], eventName: [String: String] = [:]) {
        self.lang = lang; self.mobile = mobile; self.display = display
        self.labels = labels; self.eventName = eventName
    }
}

/// One row of `GET /locales`.
public struct LocaleEntry: Sendable, Equatable, Decodable {
    public var code: String
    public var name: String
}

/// `GET /servers` (api.md §5.11): a directory, not a whitelist.
public struct ServerDirectory: Sendable, Equatable, Decodable {
    public var servers: [ServerEntry]
}

public struct ServerEntry: Sendable, Equatable, Decodable {
    public var name: String
    public var url: String
    public var kind: String
}

/// `meet_live { live }` — the same event and shape on both servers (api.md §2.1, §3).
public struct MeetLive: Sendable, Equatable {
    public var live: Bool
}
