import SwiftUI
import SplouchCore

/// A CSS hex colour as components: `#rgb`, `#rrggbb`, `#rrggbbaa`. Anything
/// else is clear, which never happens for a key `ThemeColors` has defaulted (T-07).
public struct RGBA: Equatable, Sendable {
    public var r, g, b, a: Double

    public init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard let v = UInt64(s, radix: 16) else { r = 0; g = 0; b = 0; a = 0; return }
        switch s.count {
        case 6:
            r = Double((v >> 16) & 0xFF) / 255; g = Double((v >> 8) & 0xFF) / 255; b = Double(v & 0xFF) / 255; a = 1
        case 8:
            r = Double((v >> 24) & 0xFF) / 255; g = Double((v >> 16) & 0xFF) / 255; b = Double((v >> 8) & 0xFF) / 255
            a = Double(v & 0xFF) / 255
        default:
            r = 0; g = 0; b = 0; a = 0
        }
    }

    public var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }

    /// Linear blend, `t` from 0 (self) to 1 (other).
    public func blended(with o: RGBA, by t: Double) -> RGBA {
        let k = min(1, max(0, t))
        var out = self
        out.r += (o.r - r) * k; out.g += (o.g - g) * k; out.b += (o.b - b) * k; out.a += (o.a - a) * k
        return out
    }
}

public extension Color {
    init(hex: String) { self = RGBA(hex: hex).color }
}

/// The palette as Colors, built once per `ThemeColors`.
public struct Palette: Equatable, Sendable {
    public let bg, headerBg, headerBorder, headerLabel, headerValue: Color
    public let thText, thBg, rowOdd, rowEven, rowText: Color
    public let time, deltaBetter, deltaWorse: Color
    public let scheduleEvent, scheduleTime, scheduleName, scheduleClub: Color
    private let rowTextRGBA, timeRGBA: RGBA

    /// The lane-number pulse colour between row text (0) and timing colour (1).
    public func pulseColor(_ mix: Double) -> Color {
        rowTextRGBA.blended(with: timeRGBA, by: mix).color
    }

    public init(_ c: ThemeColors) {
        rowTextRGBA = RGBA(hex: c.rowText); timeRGBA = RGBA(hex: c.time)
        bg = Color(hex: c.bg); headerBg = Color(hex: c.headerBg); headerBorder = Color(hex: c.headerBorder)
        headerLabel = Color(hex: c.headerLabel); headerValue = Color(hex: c.headerValue)
        thText = Color(hex: c.thText); thBg = Color(hex: c.thBg)
        rowOdd = Color(hex: c.rowOdd); rowEven = Color(hex: c.rowEven); rowText = Color(hex: c.rowText)
        time = Color(hex: c.time); deltaBetter = Color(hex: c.deltaBetter); deltaWorse = Color(hex: c.deltaWorse)
        scheduleEvent = Color(hex: c.scheduleEvent); scheduleTime = Color(hex: c.scheduleTime)
        scheduleName = Color(hex: c.scheduleName); scheduleClub = Color(hex: c.scheduleClub)
    }
}

/// The three font roles (T-03). The faces are bundled with the app under the
/// PostScript names below; a name the bundle lacks falls back to the system
/// monospace rather than to nothing.
public struct Faces: Equatable, Sendable {
    public let family: String
    public let digits: String
    public let timing: String

    /// Face name as the server sends it → PostScript name of the bundled file.
    public static let bundled: [String: String] = [
        "Overpass Mono": "OverpassMono-Regular",
        "DSEG7Classic": "DSEG7Classic-Regular",
        "DSEG14Classic": "DSEG14Classic-Regular",
        "Share Tech Mono": "ShareTechMono-Regular",
        "Orbitron": "Orbitron-Regular",
        "Roboto Mono": "RobotoMono-Regular",
    ]

    public init(_ f: ThemeFonts) {
        family = f.family; digits = f.digits; timing = f.timing
    }

    /// `fixedSize:` rather than `size:`, which is not a detail: `Font.custom(_:size:)`
    /// scales with Dynamic Type all by itself, and `.system(size:weight:design:)`
    /// below does not. So a bundled face grew with the setting and the fallback
    /// stood still — and the Schedule tab, which applies its own `typeScale`
    /// multiplier on top (see `HeatCard`), scaled a bundled face by the *square*
    /// of the setting. At the largest accessibility size that is 2.67 × 2.67 ≈
    /// 7×: a 14pt seed time came out around 100pt and its column measured 518pt
    /// on a 402pt screen, which pushed every card off the side of the display.
    /// The board's sizes are computed from the height its rows have to share
    /// (L-16) and were never meant to move either.
    ///
    /// Both paths are now fixed, so a size means the same thing whichever face
    /// the server names, and scaling is the caller's to do and only once.
    public static func font(_ name: String, size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if let ps = bundled[name] ?? bundled.first(where: { $0.key.caseInsensitiveCompare(name) == .orderedSame })?.value {
            return .custom(ps, fixedSize: size)
        }
        return .system(size: size, weight: weight, design: .monospaced)
    }

    public func text(_ size: CGFloat, weight: Font.Weight = .regular) -> Font { Self.font(family, size: size, weight: weight) }
    public func clock(_ size: CGFloat) -> Font { Self.font(digits, size: size) }
    public func timing(_ size: CGFloat, weight: Font.Weight = .regular) -> Font { Self.font(timing, size: size, weight: weight) }
}

/// L-17 / R-08: shrink to fit, ellipsis only as a floor.
public extension View {
    func fitOneLine(minimumScale: CGFloat = 0.5) -> some View {
        self.lineLimit(1).minimumScaleFactor(minimumScale).truncationMode(.tail)
    }
}

public extension RGBA {
    /// Rec. 709 luma against the usual midpoint. A meet themes itself (app.md
    /// §7), so the system chrome drawn over its board — sheets, alerts, the
    /// menu — has to know which way the board leans.
    var isDark: Bool { 0.2126 * r + 0.7152 * g + 0.0722 * b < 0.5 }
}

/// The platform's empty state, drawn the same way wherever a tab has nothing
/// to show. The words stay the server's (T-05) and each is a single line, so it
/// becomes the title and nothing is invented to fill a description.
///
/// Inside a `ScrollView` it takes the container's height to centre in, which
/// leaves the view scrollable so A-05's pull-to-refresh still works on an empty
/// tab. Inside a `List` it must not: a list row is a self-sizing collection view
/// cell, so the height it reports is part of what `containerRelativeFrame`
/// measures against. Each layout pass grew the row by the inset it had just
/// added, and after a hundred of them UIKit's feedback-loop debugger traps —
/// the app died on the picker's own "server unreachable" row, so a launch with
/// no network never got as far as showing the error. A list bounces whatever
/// its content's height, so pull-to-refresh survives the fixed frame.
struct Unavailable: View {
    let text: String
    let symbol: String
    var actionLabel: String?
    /// True in a `ScrollView`, false in a `List` — see the note above.
    var fillsContainer = true
    var action: () -> Void = {}

    var body: some View {
        let view = ContentUnavailableView {
            Label(text, systemImage: symbol)
        } actions: {
            if let actionLabel { Button(actionLabel, action: action) }
        }
        if fillsContainer {
            view.containerRelativeFrame(.vertical)
        } else {
            view.frame(maxWidth: .infinity, minHeight: 220)
        }
    }
}

/// A card that answers the finger. `.buttonStyle(.plain)` leaves a tapped meet
/// with no response at all until the screen changes, which on iOS reads as a
/// dropped tap rather than a slow one.
struct CardButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(reduceMotion || !configuration.isPressed ? 1 : 0.98)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
    }
}
