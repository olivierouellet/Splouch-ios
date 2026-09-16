import Foundation

/// The board's palette, in two of them: one dark, one light.
///
/// **This app does not render `settings.theme_colors`.** T-01 and T-02 have the
/// board take its palette from the meet's config, and that is still what the web
/// board and the Pi display do — but on a phone the reader chooses (P-15), and a
/// preference that the next meet could overrule is not a preference. The field
/// is still decoded and still on `MeetSettings`; nothing draws from it. The cost
/// is deliberate and worth naming: an operator who themed a meet in club colours
/// sees them everywhere except here.
///
/// The two palettes are the server's own — `DEFAULT_THEME_COLORS` in
/// `server/state.py` and `server/themes/white.toml` — so a board looks like
/// Splouch either way round rather than like something this app invented.
/// Values are CSS hex strings; converting to platform colours is the view's job.
public struct ThemeColors: Sendable, Equatable {
    public var bg: String
    public var headerBg: String
    public var headerBorder: String
    public var headerLabel: String
    public var headerValue: String
    public var thText: String
    public var thBg: String
    public var rowOdd: String
    public var rowEven: String
    public var rowText: String
    public var time: String
    public var deltaBetter: String
    public var deltaWorse: String
    public var podiumGold: String
    public var podiumSilver: String
    public var podiumBronze: String
    public var scheduleEvent: String
    public var scheduleTime: String
    public var scheduleName: String
    public var scheduleClub: String

    public static let defaults: [String: String] = [
        "bg": "#0d0d0d", "header_bg": "#1a1a1a", "header_border": "#2e2e2e",
        "header_label": "#ffffff", "header_value": "#e0e0e0",
        "th_text": "#666666", "th_bg": "#1a1a1a",
        "row_odd": "#141414", "row_even": "#202020", "row_text": "#e0e0e0",
        "time": "#FFD700", "delta_better": "#4CAF50", "delta_worse": "#808080",
        "podium_gold": "#545454", "podium_silver": "#424242", "podium_bronze": "#343434",
        "schedule_event": "#3b9eff", "schedule_time": "#FFD700",
        "schedule_name": "#e0e0e0", "schedule_club": "#666666",
    ]

    /// `server/themes/white.toml`, minus the two keys only the Qt display draws
    /// (`connection_lost`, `connection_lost_text`).
    public static let lightDefaults: [String: String] = [
        "bg": "#f8f8f8", "header_bg": "#ffffff", "header_border": "#dddddd",
        "header_label": "#333333", "header_value": "#111111",
        "th_text": "#888888", "th_bg": "#f0f0f0",
        "row_odd": "#f5f5f5", "row_even": "#ffffff", "row_text": "#111111",
        "time": "#0055aa", "delta_better": "#2e7d32", "delta_worse": "#757575",
        "podium_gold": "#d0d0d0", "podium_silver": "#dcdcdc", "podium_bronze": "#e8e8e8",
        "schedule_event": "#0055cc", "schedule_time": "#0055aa",
        "schedule_name": "#111111", "schedule_club": "#888888",
    ]

    public static let dark = ThemeColors()
    public static let light = ThemeColors(lightDefaults)

    /// Missing or empty keys fall back to the defaults rather than rendering
    /// unstyled.
    public init(_ colors: [String: String] = [:]) {
        func pick(_ k: String) -> String {
            if let v = colors[k], !v.trimmingCharacters(in: .whitespaces).isEmpty { return v }
            return Self.defaults[k]!
        }
        bg = pick("bg"); headerBg = pick("header_bg"); headerBorder = pick("header_border")
        headerLabel = pick("header_label"); headerValue = pick("header_value")
        thText = pick("th_text"); thBg = pick("th_bg")
        rowOdd = pick("row_odd"); rowEven = pick("row_even"); rowText = pick("row_text")
        time = pick("time"); deltaBetter = pick("delta_better"); deltaWorse = pick("delta_worse")
        podiumGold = pick("podium_gold"); podiumSilver = pick("podium_silver"); podiumBronze = pick("podium_bronze")
        scheduleEvent = pick("schedule_event"); scheduleTime = pick("schedule_time")
        scheduleName = pick("schedule_name"); scheduleClub = pick("schedule_club")
    }
}

/// Three font roles (app.md T-03): `family` for text, `digits` for the clock,
/// `timing` for times and deltas. Names refer to the faces bundled with the
/// app; an unknown name falls back to a system monospace in the view.
public struct ThemeFonts: Sendable, Equatable {
    public var family: String
    public var digits: String
    public var timing: String

    public static let defaults: [String: String] = [
        "family": "Overpass Mono", "digits": "DSEG7Classic", "timing": "Overpass Mono",
    ]

    public init(_ fonts: [String: String] = [:]) {
        func pick(_ k: String) -> String {
            if let v = fonts[k], !v.trimmingCharacters(in: .whitespaces).isEmpty { return v }
            return Self.defaults[k]!
        }
        family = pick("family"); digits = pick("digits"); timing = pick("timing")
    }
}
