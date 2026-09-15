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
    var timeStyle: TimeStyle = .plain
    var pulse = false

    init(_ i: Int, _ l: LaneRow) {
        laneLabel = String(i)
        name = l.name; alt = l.alt; club = l.club; time = l.time; place = l.place
        delta = DeltaFormat.text(l.deltaSeconds); deltaBetter = l.deltaBetter
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

    init(_ s: MeetSettings) {
        name = s.showName; club = s.showClub; delta = s.showDelta; place = s.showPosition
        nameHeader = s.showNameHeader; clubHeader = s.showClubHeader; deltaHeader = s.showDeltaHeader
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
    @Environment(\.palette) private var palette
    @Environment(\.faces) private var faces

    var body: some View {
        HStack(alignment: .center, spacing: compact ? 12 : 16) {
            labelled(labels["event"] ?? "", event)
            labelled(labels["heat"] ?? "", heat)
            Text(eventName)
                .font(faces.text(compact ? 13 : 16))
                .foregroundStyle(palette.headerValue)
                .fitOneLine(minimumScale: 0.6)
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

    /// The height the landscape rows share (L-16), measured by the caller.
    /// It cannot be measured here: the table sits inside a `ScrollView`, which
    /// proposes no height, so a `GeometryReader` in this body reported ~0 — the
    /// row font pinned to its 11pt floor and the whole table collapsed into a
    /// band floating mid-screen. The caller's reader is outside the scroll view
    /// and has a real height.
    let height: CGFloat
    @Environment(\.palette) private var palette
    @Environment(\.faces) private var faces

    var body: some View {
        let count = CGFloat(max(1, rows.count))
        let rowFont = isLandscape ? max(11, min(32, height * 0.42 / count)) : 17
        // Portrait rows share the height the way the landscape table does, with
        // 52pt as the floor rather than the fixed size. They used to be exactly
        // 52pt under a Spacer, so a six-lane board left a band of bare
        // background below the last lane and the stripes stopped mid-screen —
        // a table sized to its content, which is what the web page did because
        // that is what a table does. A board fills its board.
        let portraitRow = max(52, height / count)
        VStack(spacing: 0) {
            if isLandscape { header(size: rowFont) }
            ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                Group {
                    if isLandscape {
                        LandscapeRow(row: row, columns: columns, size: rowFont)
                    } else {
                        PortraitRow(row: row, columns: columns)
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
        if columns.delta { parts.append(pair("delta", row.delta)) }
        if columns.place { parts.append(pair("place", row.place)) }
        return parts.compactMap { $0 }.joined(separator: ", ")
    }

    private func header(size: CGFloat) -> some View {
        HStack(spacing: 8) {
            cell(columns.laneHeader ? labels["lane"] : nil, width: 44)
            if columns.name { cell(columns.nameHeader ? labels["name"] : nil, flex: true) }
            if columns.club { cell(columns.clubHeader ? labels["club"] : nil, width: 140) }
            cell(columns.timeHeader ? labels["time"] : nil, width: 120, trailing: true)
            if columns.delta { cell(columns.deltaHeader ? labels["delta"] : nil, width: 90, trailing: true) }
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
struct PortraitRow: View {
    let row: BoardRow
    let columns: Columns
    @Environment(\.palette) private var palette
    @Environment(\.faces) private var faces

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            LaneNumber(text: row.laneLabel, pulse: row.pulse, size: 22).frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    if columns.name {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(row.name).font(faces.text(17)).foregroundStyle(palette.rowText).fitOneLine()
                            if !row.alt.isEmpty {
                                Text(row.alt).font(faces.text(12)).foregroundStyle(palette.thText).fitOneLine()   // L-06
                            }
                        }
                    }
                    Spacer(minLength: 8)
                    if columns.club {
                        Text(row.club).font(faces.text(13)).foregroundStyle(palette.thText).fitOneLine()
                    }
                }
                HStack(spacing: 12) {
                    TimeCell(text: row.time, style: row.timeStyle, size: 20)
                    if columns.delta { DeltaCell(text: row.delta, better: row.deltaBetter, size: 14) }
                    Spacer()
                    if columns.place, !row.place.isEmpty {
                        Text("#" + row.place).font(faces.text(16, weight: .bold)).foregroundStyle(palette.headerLabel)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}

/// L-16: a full table row.
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
                Text(row.club).font(faces.text(size * 0.68)).foregroundStyle(palette.thText).fitOneLine().frame(width: 140, alignment: .leading)
            }
            TimeCell(text: row.time, style: row.timeStyle, size: size * 0.72).frame(width: 120, alignment: .trailing)
            if columns.delta {
                DeltaCell(text: row.delta, better: row.deltaBetter, size: size * 0.58).frame(width: 90, alignment: .trailing)
            }
            if columns.place {
                Text(row.place).font(faces.text(size * 0.8, weight: .bold)).foregroundStyle(palette.headerLabel)
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

/// L-11: running is dimmed; a stop plays a one-shot flash from white to the
/// timing colour, keyed on the edge generation so a second finish replays it.
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

    private var color: Color {
        switch style {
        case .running: Color(white: 0.63)
        case .locked: flashing ? .white : palette.time
        case .plain: palette.time
        }
    }
}

struct DeltaCell: View {
    let text: String
    let better: Bool?
    let size: CGFloat
    @Environment(\.palette) private var palette
    @Environment(\.faces) private var faces

    var body: some View {
        Text(text)
            .font(faces.timing(size))
            .monospacedDigit()
            .foregroundStyle(better == true ? palette.deltaBetter : palette.deltaWorse)
    }
}
