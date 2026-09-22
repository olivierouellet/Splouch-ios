import SwiftUI
import Testing
@testable import SplouchCore
@testable import SplouchUI

/// T-07 / P-15. The colours arrive as CSS hex from a server that is not this
/// app's, so the parsing is the boundary — everything above it is `Color`.
@Suite struct RGBATests {
    @Test func theThreeHexLengthsAllParse() {
        #expect(RGBA(hex: "#ff0000") == RGBA(hex: "#f00"))
        #expect(RGBA(hex: "#ffffff").r == 1)
        #expect(RGBA(hex: "#000000") == RGBA(hex: "#000"))

        let mid = RGBA(hex: "#808080")
        #expect(abs(mid.r - 128.0 / 255) < 0.0001)
        #expect(mid.r == mid.g && mid.g == mid.b)
        #expect(mid.a == 1)
    }

    @Test func eightDigitsCarryAnAlpha() {
        let half = RGBA(hex: "#ff000080")
        #expect(half.r == 1)
        #expect(half.g == 0)
        #expect(abs(half.a - 128.0 / 255) < 0.0001)
        #expect(RGBA(hex: "#ff0000ff").a == 1)
        #expect(RGBA(hex: "#ff000000").a == 0)
    }

    /// The hash is optional and the surrounding whitespace is not the server's
    /// intent. A meet's `theme_colors` is typed by an operator.
    @Test func theHashAndSurroundingSpaceAreOptional() {
        #expect(RGBA(hex: "ff0000") == RGBA(hex: "#ff0000"))
        #expect(RGBA(hex: "  #ff0000  ") == RGBA(hex: "#ff0000"))
        #expect(RGBA(hex: " f00 ") == RGBA(hex: "#ff0000"))
    }

    /// Anything else is clear rather than a crash or a guess. T-07 says this
    /// never happens for a key `ThemeColors` has defaulted — but the value comes
    /// off a wire, and "never" is the server's promise, not this app's.
    @Test func anythingElseIsClear() {
        let clear = RGBA(hex: "")
        for junk in ["", "#", "nonsense", "#12345", "#1234567", "#gg0000", "rgb(255,0,0)"] {
            let c = RGBA(hex: junk)
            #expect(c.a == 0, "\(junk) should be clear")
            #expect(c == clear, "\(junk) should be clear")
        }
    }

    /// Rec. 709 luma, which decides which way the system chrome over a board
    /// leans. The two shipped palettes have to land on opposite sides of it or
    /// a sheet is drawn unreadable over one of them.
    @Test func lumaSeparatesTheTwoShippedPalettes() {
        #expect(RGBA(hex: ThemeColors.dark.bg).isDark)
        #expect(!RGBA(hex: ThemeColors.light.bg).isDark)
        #expect(RGBA(hex: "#000000").isDark)
        #expect(!RGBA(hex: "#ffffff").isDark)
        // Green carries most of the luma and blue almost none, so these two
        // land on opposite sides despite being equally bright as numbers.
        #expect(!RGBA(hex: "#00ff00").isDark)
        #expect(RGBA(hex: "#0000ff").isDark)
    }

    /// L-13's lane pulse rides this between the row text and the timing colour.
    /// Out-of-range mixes are clamped rather than extrapolated past the ends.
    @Test func blendingIsClampedToItsEnds() {
        let black = RGBA(hex: "#000000")
        let white = RGBA(hex: "#ffffff")
        #expect(black.blended(with: white, by: 0) == black)
        #expect(black.blended(with: white, by: 1) == white)
        #expect(abs(black.blended(with: white, by: 0.5).r - 0.5) < 0.0001)
        #expect(black.blended(with: white, by: -3) == black)
        #expect(black.blended(with: white, by: 9) == white)
    }
}

/// T-03. A face the bundle does not have falls back to the system monospace,
/// and a size means the same thing on either path — which is what stopped the
/// Schedule tab scaling a bundled face by the square of the text-size setting.
@Suite struct FacesTests {
    @Test func everyBundledNameMapsToAPostScriptName() {
        // The keys are what a server sends in `theme_fonts`; the values are the
        // files under App/Fonts. A typo on either side is a silent fallback.
        #expect(Faces.bundled["Overpass Mono"] == "OverpassMono-Regular")
        #expect(Faces.bundled["DSEG7Classic"] == "DSEG7Classic-Regular")
        #expect(Faces.bundled.count == 6)
        #expect(Faces.bundled.values.allSatisfy { !$0.isEmpty })
    }

    /// The server's spelling is not guaranteed to match the table's, so the
    /// lookup is case-insensitive before it gives up.
    @Test func aNameIsFoundWhateverItsCase() {
        #expect(Faces.font("Overpass Mono", size: 12) == Faces.font("overpass mono", size: 12))
        #expect(Faces.font("ORBITRON", size: 12) == Faces.font("Orbitron", size: 12))
    }

    @Test func anUnknownFaceFallsBackToTheSystemMonospace() {
        let unknown = Faces.font("Comic Sans", size: 14)
        #expect(unknown == .system(size: 14, weight: .regular, design: .monospaced))
        #expect(unknown != Faces.font("Orbitron", size: 14))
    }

    @Test func theThreeRolesEachUseTheirOwnFace() {
        let f = Faces(ThemeFonts(["family": "Overpass Mono", "digits": "DSEG7Classic", "timing": "Orbitron"]))
        #expect(f.family == "Overpass Mono")
        #expect(f.digits == "DSEG7Classic")
        #expect(f.timing == "Orbitron")
        #expect(f.clock(20) == Faces.font("DSEG7Classic", size: 20))
        #expect(f.text(20) == Faces.font("Overpass Mono", size: 20))
    }
}

/// P-15: the palette is built once per `ThemeColors`, and the pulse rides
/// between two of its members.
@Suite struct PaletteTests {
    @Test func thePulseRunsFromRowTextToTheTimingColour() {
        let p = Palette(ThemeColors.dark)
        #expect(p.pulseColor(0) == Color(hex: ThemeColors.dark.rowText))
        #expect(p.pulseColor(1) == Color(hex: ThemeColors.dark.time))
        #expect(p.pulseColor(0.5) != p.pulseColor(0))
    }

    @Test func theTwoShippedPalettesDifferEverywhereItMatters() {
        let dark = Palette(ThemeColors.dark)
        let light = Palette(ThemeColors.light)
        #expect(dark != light)
        #expect(dark.bg != light.bg)
        #expect(dark.rowText != light.rowText)
    }
}
