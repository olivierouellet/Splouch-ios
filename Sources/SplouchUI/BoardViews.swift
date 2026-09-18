import SwiftUI
import SplouchCore

/// One row as both boards draw it: the Scoreboard tab's `LaneRow` and the
/// Results tab's `ResultRow` map onto this (R-04: same six columns).
struct BoardRow: Equatable {
    var laneLabel: String
    var name = ""
    var alt = ""
    var club = ""
    var time = ""
    var place = ""
    var delta = ""
    var deltaBetter: Bool?
    /// L-23: the delta cell's other tenant, while the delta itself is empty.
    /// Only the Scoreboard tab has one — a Results row is all finishes.
    var lap: LapCount?
    var timeStyle: TimeStyle = .plain
    var pulse = false

    init(_ i: Int, _ l: LaneRow, lap: LapCount? = nil) {
        laneLabel = String(i)
        name = l.name; alt = l.alt; club = l.club; time = l.time; place = l.place
        delta = DeltaFormat.text(l.deltaSeconds); deltaBetter = l.deltaBetter
        self.lap = lap
        timeStyle = l.timeStyle; pulse = l.pulse
    }

    init(_ r: ResultRow) {
        laneLabel = r.laneLabel
        name = r.name; alt = r.alt; club = r.club; time = r.time; place = r.place
        delta = DeltaFormat.text(r.deltaSeconds); deltaBetter = r.deltaBetter
        timeStyle = r.locked ? .locked(generation: 1) : .plain   // R-09
    }
}

/// Which columns show (L-07) and which headers (L-08).
struct Columns: Equatable {
    var name, club, delta, place: Bool
    var nameHeader, clubHeader, deltaHeader, placeHeader, laneHeader, timeHeader: Bool

    /// `laps` is the Scoreboard tab's alone: L-23 shares the delta *cell* with
    /// the lap count on the live board, and the Results tab is all finishes, so
    /// its delta column has one tenant and keeps its title.
    init(_ s: MeetSettings, laps: LapSettings = .off) {
        name = s.showName; club = s.showClub; delta = s.showDelta; place = s.showPosition
        // L-23: with laps on, that column holds lengths for most of a heat, and
        // a `Δ` over a column of small integers reads as a claim about them. It
        // stays hidden once the heat settles too — a title that appeared at the
        // finish would be the moving header L-23 exists to refuse.
        nameHeader = s.showNameHeader; clubHeader = s.showClubHeader
        deltaHeader = s.showDeltaHeader && !laps.show
        placeHeader = s.showPositionHeader; laneHeader = s.showLaneHeader; timeHeader = s.showTimeHeader
    }
}

/// The EVENT / HEAT / event name / wall clock bar (L-01, L-02, L-03, R-03).
struct BoardHeader: View {
    let event: String
    let heat: String
    let eventName: String
    let labels: [String: String]
    /// Landscape puts this row inside the navigation bar, beside the back
    /// button, rather than under it — the bar was otherwise a band of empty
    /// space with one button in the corner. Everything shrinks to fit a bar.
    var compact = false
    /// The bar shows the clock as its own trailing item: one centred item
    /// holding all four squeezed them until the clock truncated to an ellipsis.
    var showsClock = true

    /// What this costs a portrait board, measured on an iPhone 17. `MeetShell`
    /// decides from it whether the lanes still fit underneath.
    static let portraitBand: CGFloat = 58
    @Environment(\.palette) private var palette
    @Environment(\.faces) private var faces

    var body: some View {
        HStack(alignment: .center, spacing: compact ? 12 : 16) {
            labelled(labels["event"] ?? "", event)
            labelled(labels["heat"] ?? "", heat)
            // Portrait wraps rather than truncating. The name is the longest
            // thing in the row and portrait is the narrow axis: a composed
            // relay name runs to 46 characters — "4x200 m quatre nages relais
            //   —  Garçons Sénior" — against room for about 29 at the 0.6
            // floor, so one line dropped the gender and the age group
            // entirely, not a word or two off the end. The limit is 2, not a
            // wrap with no ceiling, so the board below keeps a known height.
            // Landscape stays on one line whatever it costs: that copy lives
            // in the navigation bar, which is one row high (see MeetShell).
            Text(eventName)
                .font(faces.text(compact ? 13 : 16))
                .foregroundStyle(palette.headerValue)
                .lineLimit(compact ? 1 : 2)
                .minimumScaleFactor(0.6)
                .truncationMode(.tail)
                .multilineTextAlignment(.center)
                // A wrapped line is taller than the font, and an HStack hands
                // a Text its ideal height unless it is told to take the height
                // the width it got actually needs.
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .center)
            if showsClock { WallClock(size: compact ? 15 : 22) }
        }
        .padding(.horizontal, compact ? 0 : 12)
        .padding(.vertical, compact ? 0 : 8)
        // No background and no hairline: this used to be a bar of its own, with
        // a `border-bottom` carried over from the web shell. It now sits under
        // the real navigation bar, and two stacked bars for one screen is one
        // too many — the table's first stripe is edge enough.
    }

    @ViewBuilder private func labelled(_ label: String, _ value: String) -> some View {
        let name = Text(label).font(faces.text(compact ? 10 : 10)).foregroundStyle(palette.headerLabel)
        let number = Text(value.isEmpty ? " " : value)
            .font(faces.clock(compact ? 17 : 26)).foregroundStyle(palette.headerValue)
        // The word and its number are one thing to read, and a header with no
        // number yet is nothing to read at all — otherwise VoiceOver stops on
        // "EVENT" and says no more.
        Group {
            if compact {
                // A navigation bar is one row high, so the label sits beside
                // its number rather than over it.
                HStack(alignment: .firstTextBaseline, spacing: 4) { name; number }.fixedSize()
            } else {
                VStack(spacing: 3) { name; number }.fixedSize()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHidden(value.isEmpty)
    }
}

/// L-03: device local time, `HH:MM`, ticking every second. Always 24-hour, as
/// the board is, whatever the locale's clock preference.
struct WallClock: View {
    var size: CGFloat = 22
    @Environment(\.palette) private var palette
    @Environment(\.faces) private var faces

    static func hhmm(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            Text(Self.hhmm(ctx.date))
                .font(faces.clock(size))
                .foregroundStyle(palette.headerValue)
                .monospacedDigit()
        }
    }
}

/// The lane table, portrait two-line rows (L-15) or a landscape table (L-16).
struct BoardTable: View {
    let rows: [BoardRow]
    let columns: Columns
    let labels: [String: String]
    let isLandscape: Bool
    /// How far the table holds off the floating tab bar, so the last lane is
    /// not read against the glass.
    static let bottomGap: CGFloat = 14

    /// The height the lanes share: the whole scroll area, less the clearance.
    ///
    /// Not less `safeAreaInsets.bottom`. On iOS 26 the scroll area runs under
    /// the floating tab bar, and every attempt to hold the lanes above it —
    /// stopping the table short, or padding the last lane's stripe past its
    /// content — traded a bare band or a visibly deeper last lane for the
    /// clearance. The lanes are equal and they fill: the bar floats over the
    /// foot of the last one, and getting that lane back is the tab bar's job,
    /// not the table's.
    static func tableHeight(in geo: GeometryProxy) -> CGFloat {
        max(0, geo.size.height - bottomGap)
    }


    /// How far the portrait type may be shrunk to keep a heat on one screen.
    /// Past this the table overflows and scrolls, which is the honest answer:
    /// twelve lanes of relay at 8pt would fit and be unreadable.
    static let portraitTypeFloor: CGFloat = 0.72

    /// The height the landscape rows share (L-16), measured by the caller.
    /// It cannot be measured here: the table sits inside a `ScrollView`, which
    /// proposes no height, so a `GeometryReader` in this body reported ~0 — the
    /// row font pinned to its 11pt floor and the whole table collapsed into a
    /// band floating mid-screen. The caller's reader is outside the scroll view
    /// and has a real height.
    let height: CGFloat
    @Environment(\.palette) private var palette
    @Environment(\.faces) private var faces

    /// How tall a row's type may be, as a fraction of the height that row is
    /// given. It was 0.42, which left well over half of every row as leading:
    /// on a six-lane board in landscape the rows are 55pt tall and the numbers a
    /// spectator came to read were set at 23. A `LandscapeRow` has no vertical
    /// padding at all, so this — not padding — is the whole of what held them
    /// down. 0.55 still leaves room for a name with an alt line under it
    /// (0.85 + 0.55 of the row font, so 77% of the row).
    private static let typeShare: CGFloat = 0.55
    /// Below this the column titles cost more height than their words are worth,
    /// so the table drops them and gives the band back to the lanes.
    private static let headerFloor: CGFloat = 14

    /// The row font, and whether the titles survive at that size. Sized once with
    /// the header's band withheld; if that comes out cramped the header goes and
    /// the rows are sized again over the whole height.
    private func landscapeType() -> (rowFont: CGFloat, showsHeader: Bool) {
        let count = CGFloat(max(1, rows.count))
        func font(_ available: CGFloat) -> CGFloat {
            max(11, min(32, available * Self.typeShare / count))
        }
        let withHeader = font(height - Self.headerBand)
        if withHeader >= Self.headerFloor { return (withHeader, true) }
        return (font(height), false)
    }

    /// What `header(size:)` costs: its own line plus 4pt above and below.
    private static let headerBand: CGFloat = 26

    /// A lane's natural height, and the same lane carrying a relay name. Both
    /// come off the rulers below, and are 0 until the first layout has run.
    @State private var laneIdeal: CGFloat = 0
    @State private var laneIdealWithAlt: CGFloat = 0

    var body: some View {
        let count = CGFloat(max(1, rows.count))
        let landscape = landscapeType()
        let rowFont = isLandscape ? landscape.rowFont : 17
        // Portrait rows share the height the way the landscape table does. They
        // used to be exactly 52pt under a Spacer, so a six-lane board left a
        // band of bare background below the last lane and the stripes stopped
        // mid-screen — a table sized to its content, which is what the web page
        // did because that is what a table does. A board fills its board.
        //
        // The 52pt floor that replaced it is now gone too. It was what stopped
        // twelve lanes fitting: twelve of them want 624pt against the 603 a
        // phone has, and the miss was the floor, not the type. The share each
        // row gets is the floor, and the type shrinks to meet it.
        let portraitRow = height / count
        // What the rows in *this* heat want — a relay with alt names needs a
        // third line, so the same twelve lanes ask for 780pt rather than 600.
        //
        // The relay name is what goes first, before any type shrinks: it is the
        // one line on the row that is not a swimmer, a time or a place, and a
        // team name set at 9pt to keep it helps nobody. Dropped, the row is back
        // to two lines and everything on it stays the size it should be.
        // Until the rulers have reported, a row wants exactly its share: the
        // first frame draws at full size and settles a frame later, which beats
        // guessing a number that is right on one phone and wrong on the rest.
        let wantPlain = laneIdeal > 0 ? laneIdeal : portraitRow
        let wantAlt = laneIdealWithAlt > 0 ? laneIdealWithAlt : wantPlain
        let showsAlt = rows.contains { !$0.alt.isEmpty } && portraitRow >= wantAlt
        let portraitWant = showsAlt ? wantAlt : wantPlain
        let portraitScale = min(1, max(Self.portraitTypeFloor, portraitRow / portraitWant))
        VStack(spacing: 0) {
            if isLandscape, landscape.showsHeader { header(size: rowFont) }
            ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                Group {
                    if isLandscape {
                        LandscapeRow(row: row, columns: columns, size: rowFont)
                    } else {
                        PortraitRow(row: row, columns: columns, scale: portraitScale, showsAlt: showsAlt)
                    }
                }
                .frame(maxWidth: .infinity,
                       minHeight: isLandscape ? 0 : portraitRow,
                       maxHeight: isLandscape ? .infinity : nil)
                .background(i % 2 == 0 ? palette.rowOdd : palette.rowEven)
                // A lane is one thing. Left as six separate Texts, VoiceOver
                // read "1", "Sara Leblanc", "CAMO", "2:24.10" as four unrelated
                // elements with nothing tying them to a lane.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spoken(row))
            }
        }
        // Exactly the height in landscape, so rows with no minimum actually
        // divide it; in portrait the rows above set it, and overflow scrolls.
        .frame(height: isLandscape ? height : nil)
        .background(alignment: .top) { rulers }
        .preference(key: LaneIdealKey.self, value: portraitWant)
    }

    /// One lane drawn at full size and never shown, so the table can ask how
    /// tall a row is instead of being told. It lives in a `background`, which is
    /// handed the table's width and proposes nothing back, so measuring it
    /// cannot move the table that measured it — the feedback a `GeometryReader`
    /// among the rows would have made.
    @ViewBuilder private var rulers: some View {
        if !isLandscape, let first = rows.first {
            VStack(spacing: 0) {
                PortraitRow(row: first, columns: columns, scale: 1, showsAlt: false)
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { laneIdeal = $0 }
                if let relay = rows.first(where: { !$0.alt.isEmpty }) {
                    PortraitRow(row: relay, columns: columns, scale: 1, showsAlt: true)
                        .fixedSize(horizontal: false, vertical: true)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { laneIdealWithAlt = $0 }
                }
                Spacer(minLength: 0)
            }
            .hidden()
        }
    }

    /// The row as one sentence, in the server's own column words (T-04) so it
    /// is spoken in the meet's language rather than the app's. An empty lane
    /// says only its number, which is the truth about it.
    private func spoken(_ row: BoardRow) -> String {
        func pair(_ key: String, _ value: String) -> String? {
            value.isEmpty ? nil : [labels[key], value].compactMap { $0 }.joined(separator: " ")
        }
        var parts = [pair("lane", row.laneLabel)]
        if columns.name {
            parts.append(row.name.isEmpty ? nil : row.name)
            parts.append(row.alt.isEmpty ? nil : row.alt)
        }
        if columns.club { parts.append(pair("club", row.club)) }
        parts.append(pair("time", row.time))
        // L-23: whichever tenant the cell has. The delta keeps the server's own
        // column word; the lap has none to keep — see `Native.laps`.
        if columns.delta {
            if row.delta.isEmpty, let lap = row.lap {
                parts.append(Native.laps + " " + lap.text)
            } else {
                parts.append(pair("delta", row.delta))
            }
        }
        if columns.place { parts.append(pair("place", row.place)) }
        return parts.compactMap { $0 }.joined(separator: ", ")
    }

    private func header(size: CGFloat) -> some View {
        HStack(spacing: 8) {
            cell(columns.laneHeader ? labels["lane"] : nil, width: 44)
            if columns.name { cell(columns.nameHeader ? labels["name"] : nil, flex: true) }
            if columns.club { cell(columns.clubHeader ? labels["club"] : nil, width: 140) }
            cell(columns.timeHeader ? labels["time"] : nil, width: 130, trailing: true)
            if columns.delta { cell(columns.deltaHeader ? labels["delta"] : nil, width: 110, trailing: true) }
            if columns.place { cell(columns.placeHeader ? labels["place"] : nil, width: 50, trailing: true) }
        }
        .font(faces.text(max(10, size * 0.55)))
        .foregroundStyle(palette.thText)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(palette.thBg)
    }

    @ViewBuilder
    private func cell(_ text: String?, width: CGFloat? = nil, flex: Bool = false, trailing: Bool = false) -> some View {
        let t = Text(text ?? "").fitOneLine()
        if flex {
            t.frame(maxWidth: .infinity, alignment: trailing ? .trailing : .leading)
        } else {
            t.frame(width: width, alignment: trailing ? .trailing : .leading)
        }
    }
}

/// L-15: lane number spanning the left; name with club right-aligned on line
/// one; time, delta and place on line two; `#` before a place, nothing without.
///
/// The club, the delta and the place read at the name's size rather than four
/// or five points under it. They were sized as annotations on a row whose only
/// real content was the name and the time, but on a results board the club and
/// the place are half of what a spectator is there for, and a delta nobody can
/// read from a seat is a column of wasted width. Colour still carries the
/// hierarchy — the club stays `th_text` against the name's `row_text` — so
/// matching their sizes does not make them compete.
struct PortraitRow: View {
    let row: BoardRow
    let columns: Columns
    /// 1 when the heat fits at the sizes below, less when the lanes have to
    /// share the screen more tightly. Everything in the row scales together so
    /// the hierarchy holds at any count — see `BoardTable.portraitTypeFloor`.
    var scale: CGFloat = 1
    /// False once the lanes are too tight to spend a line on the relay's name.
    var showsAlt = true
    @Environment(\.palette) private var palette
    @Environment(\.faces) private var faces

    var body: some View {
        HStack(alignment: .center, spacing: 10 * scale) {
            LaneNumber(text: row.laneLabel, pulse: row.pulse, size: 22 * scale).frame(width: 34 * scale)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    if columns.name {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(row.name).font(faces.text(17 * scale)).foregroundStyle(palette.rowText).fitOneLine()
                            if !row.alt.isEmpty, showsAlt {
                                Text(row.alt).font(faces.text(12 * scale)).foregroundStyle(palette.thText).fitOneLine()   // L-06
                            }
                        }
                    }
                    Spacer(minLength: 8)
                    if columns.club {
                        Text(row.club).font(faces.text(17 * scale)).foregroundStyle(palette.thText).fitOneLine()
                    }
                }
                HStack(spacing: 12 * scale) {
                    TimeCell(text: row.time, style: row.timeStyle, size: 20 * scale)
                    // No fixed column here — a compact row lays its second line
                    // out in flow — so the cell is sized to what it holds and
                    // L-23's centring has nothing to centre in. It still swaps
                    // tenant and colour on the same rule as the table's.
                    if columns.delta {
                        DeltaCell(text: row.delta, better: row.deltaBetter, lap: row.lap, size: 17 * scale)
                            .fixedSize()
                    }
                    Spacer()
                    if columns.place, !row.place.isEmpty {
                        Text("#" + row.place).font(faces.text(18 * scale, weight: .bold)).foregroundStyle(palette.headerLabel)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6 * scale)
    }
}

/// What one lane wants on this phone, at this text size, with these words in
/// it — measured, never assumed. Travels up to the tab, which is the only view
/// that also knows what the board's own header band costs.
struct LaneIdealKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Whether the lanes need the navigation bar to take the header row off them.
struct BoardNeedsBarKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

/// L-16: a full table row.
///
/// The time, the delta and the place are set from the row font the way the name
/// is, rather than two thirds of it. A six-lane board in landscape has height to
/// spare — the row font only claims 42% of what a row is given — and the three
/// numbers a spectator came to read were the smallest things on it. The place
/// takes the full row font: it is one character, it is the answer, and it has a
/// column to itself. Time and delta gained 10pt of column each to hold it.
struct LandscapeRow: View {
    let row: BoardRow
    let columns: Columns
    let size: CGFloat
    @Environment(\.palette) private var palette
    @Environment(\.faces) private var faces

    var body: some View {
        HStack(spacing: 8) {
            LaneNumber(text: row.laneLabel, pulse: row.pulse, size: size).frame(width: 44, alignment: .leading)
            if columns.name {
                VStack(alignment: .leading, spacing: 0) {
                    Text(row.name).font(faces.text(size * 0.85)).foregroundStyle(palette.rowText).fitOneLine()
                    if !row.alt.isEmpty {
                        Text(row.alt).font(faces.text(size * 0.55)).foregroundStyle(palette.thText).fitOneLine()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if columns.club {
                Text(row.club).font(faces.text(size * 0.85)).foregroundStyle(palette.thText).fitOneLine().frame(width: 140, alignment: .leading)
            }
            TimeCell(text: row.time, style: row.timeStyle, size: size * 0.85).frame(width: 130, alignment: .trailing)
            if columns.delta {
                // The column's width is the cell's; the cell decides where in
                // it the number sits, because the lap centres and the delta does
                // not (L-23).
                DeltaCell(text: row.delta, better: row.deltaBetter, lap: row.lap, size: size * 0.85)
                    .frame(width: 110)
            }
            if columns.place {
                Text(row.place).font(faces.text(size, weight: .bold)).foregroundStyle(palette.headerLabel)
                    .frame(width: 50, alignment: .trailing)
            }
        }
        .padding(.horizontal, 8)
    }
}

/// The lane number, pulsing between row and timing colour while the lane runs
/// with no clock to show (L-12). A cycle begins and ends on the row colour and
/// is allowed to finish before the pulse is dropped, so stopping every lane at
/// once does not flick the whole column.
struct LaneNumber: View {
    let text: String
    let pulse: Bool
    let size: CGFloat
    @Environment(\.palette) private var palette
    @Environment(\.faces) private var faces
    @State private var stopAfterCycle: Int?

    var body: some View {
        Group {
            if pulse || stopAfterCycle != nil {
                TimelineView(.animation) { ctx in
                    let t = ctx.date.timeIntervalSinceReferenceDate
                    let cycle = Int(t.rounded(.down))
                    let phase = t - Double(cycle)   // 0…1 over one second
                    let done = stopAfterCycle.map { cycle > $0 } ?? false
                    let mix = done ? 0 : (1 - cos(phase * 2 * .pi)) / 2
                    label(mix: mix)
                        .onChange(of: done) { _, d in if d { stopAfterCycle = nil } }
                }
            } else {
                label(mix: 0)
            }
        }
        .onChange(of: pulse) { _, on in
            stopAfterCycle = on ? nil : Int(Date().timeIntervalSinceReferenceDate.rounded(.down))
        }
    }

    private func label(mix: Double) -> some View {
        Text(text)
            .font(faces.text(size))
            .foregroundStyle(palette.pulseColor(mix))
    }
}

/// L-11: running is dimmed; a stop plays a one-shot flash from the row's own
/// text colour to the timing colour, keyed on the edge generation so a second
/// finish replays it.
struct TimeCell: View {
    let text: String
    let style: TimeStyle
    let size: CGFloat
    @Environment(\.palette) private var palette
    @Environment(\.faces) private var faces
    @State private var flashing = false

    private var generation: Int {
        if case .locked(let g) = style { return g }
        return 0
    }

    var body: some View {
        Text(text)
            .font(faces.timing(size))
            .monospacedDigit()
            .foregroundStyle(color)
            .fitOneLine()
            .onChange(of: generation) { _, g in
                guard g > 0 else { return }
                flashing = true
                withAnimation(.easeOut(duration: 0.8)) { flashing = false }
            }
    }

    // Both of these were fixed greys — `Color(white: 0.63)` and `.white` — from
    // a board that was only ever dark. A light theme (`white.toml` ships one)
    // turns the first into pale grey on near-white and the second into a flash
    // that cannot be seen at all, which is the one moment on the board that has
    // to be.
    //
    // `rowText` at 70% lands within a couple of percent of the old grey on the
    // dark board, because it dims against the row it sits on rather than
    // against an assumed black; and the flash starts from whatever the row
    // writes its text in, which is the highest-contrast colour the theme has
    // against that row whichever way round it is.
    private var color: Color {
        switch style {
        case .running: palette.rowText.opacity(0.7)
        case .locked: flashing ? palette.rowText : palette.time
        case .plain: palette.time
        }
    }
}

/// One cell, two tenants (L-23). While a lane is swimming it carries that lane's
/// lengths, centred, in the header's accent colour; at the finish the delta takes
/// the cell back, right where every other number on the row ends, in its
/// better/worse colour. The column header never changes — the colours and the
/// moment of the swap are what say which tenant is on screen.
///
/// Which tenant it is was settled upstream, from merged state alone
/// (`ScoreboardState.lap(lane:_:)`); this view only draws the answer. There is no
/// animation on the handover and none on the final stretch: an earlier version
/// pulsed that and it was taken out on purpose. A static colour change is the
/// whole effect.
///
/// All four colours come off the palette — `headerLabel`, `time`, `deltaBetter`,
/// `deltaWorse` — and none is written here. The palette is the reader's (P-15)
/// rather than the meet's, which is this app's standing divergence from T-01;
/// see `ThemeColors`.
struct DeltaCell: View {
    let text: String
    let better: Bool?
    var lap: LapCount?
    let size: CGFloat
    @Environment(\.palette) private var palette
    @Environment(\.faces) private var faces

    /// The lap is the tenant only while the delta has nothing to say. Both tests
    /// already ran upstream; this is the belt to that braces, for the frame where
    /// the two arrive together.
    private var showsLap: Bool { lap != nil && text.isEmpty }

    var body: some View {
        Text(showsLap ? (lap?.text ?? "") : text)
            .font(faces.timing(size))
            .monospacedDigit()
            .foregroundStyle(colour)
            // Its column is fixed and it is now set at the name's size, so a
            // four-lane board at the row-font cap could ask for more width than
            // the column has. Shrink rather than wrap: a delta on two lines is
            // not a delta.
            .fitOneLine(minimumScale: 0.7)
            .frame(maxWidth: .infinity, alignment: showsLap ? .center : .trailing)
    }

    private var colour: Color {
        guard showsLap else { return better == true ? palette.deltaBetter : palette.deltaWorse }
        // The final stretch takes the colour a stopped chrono has; every other
        // length takes the accent the EVENT and HEAT words use, because a lap is
        // a label on the race and not a number anyone races against.
        return lap?.isFinal == true ? palette.time : palette.headerLabel
    }
}
