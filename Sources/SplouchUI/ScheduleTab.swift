import SwiftUI
import SplouchCore

/// The Schedule tab (app.md §5.1).
struct ScheduleTab: View {
    let ctx: MeetContext
    @Environment(\.scenePhase) private var scenePhase
    /// S-06: once per appearance, re-armed on returning to the foreground.
    @State private var scrolledToCurrent = false

    var body: some View {
        let heats = ctx.schedule?.heats ?? []
        let visible = ScheduleView.visible(heats, filter: ctx.filter, current: ctx.currentHeat)
        // One seed column for the whole screen, not one per card: a spectator
        // scrolling past a hundred heats reads the times as a column, and a
        // width that changed card to card would undo that.
        let seedTemplate = ScheduleView.widestSeedTime(visible)
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if ctx.schedule != nil, heats.isEmpty {
                        // S-07: on a Pi an empty list means no meet file is loaded;
                        // on a cloud the meet is there but carries no schedule yet.
                        Unavailable(text: ctx.strings.mobile(ctx.kind == .pi ? "no_meet" : "no_schedule"),
                                    symbol: "calendar")
                    } else if ctx.schedule == nil {
                        if ctx.scheduleFailed {
                            Unavailable(text: Native.serverUnreachable, symbol: "wifi.exclamationmark",
                                        actionLabel: Native.retry) { Task { await ctx.refresh() } }
                        } else {
                            ProgressView().padding(40)
                        }
                    } else if visible.isEmpty {
                        // S-19: no swimmer matches these filters. Offer the way
                        // out only when there is something to clear — "nothing
                        // upcoming" is not a filter the reset would undo.
                        Unavailable(text: ctx.strings.mobile(ctx.filter.upcomingOnly && !ctx.filter.isFiltering ? "no_upcoming" : "no_matches"),
                                    symbol: "magnifyingglass",
                                    actionLabel: ctx.filter.isFiltering ? ctx.strings.mobile("reset_filters") : nil) {
                            ctx.filter.reset()
                        }
                    } else {
                        ForEach(visible, id: \.heat.id) { v in
                            HeatCard(heat: v, labels: ctx.labels, eventName: ctx.eventName(v.heat.eventName, parts: v.heat.eventNameParts),
                                     seedTemplate: seedTemplate)
                                .id(v.heat.id)
                        }
                    }
                }
            }
            .refreshable { await ctx.refresh() }
            .onChange(of: visible.first(where: \.isCurrent)?.heat.id, initial: true) { _, id in
                guard let id, !scrolledToCurrent else { return }
                scrolledToCurrent = true
                withAnimation { proxy.scrollTo(id, anchor: .top) }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { scrolledToCurrent = false }
            }
            .onAppear { scrolledToCurrent = false }
        }
    }
}


extension ScheduleHeat {
    var id: String { event + "/" + heat }
}

/// S-01 to S-05: one heat as a card.
struct HeatCard: View {
    let heat: VisibleHeat
    let labels: [String: String]
    let eventName: String
    /// The widest seed time on screen, which sizes the seed column. Empty when
    /// no lane has one — see `seedColumn`.
    let seedTemplate: String
    @Environment(\.palette) private var palette
    @Environment(\.faces) private var faces
    /// The schedule is the screen a spectator reads hardest — hunting one name
    /// among several hundred — so its type follows the device's text size.
    ///
    /// A multiplier rather than `Font.custom(_:size:relativeTo:)`: that only
    /// scales a face the bundle actually has, and T-03 falls back to the system
    /// monospace for a name it does not know, which would then be the one line
    /// on screen ignoring the setting. Scaling the size scales both paths alike.
    /// The board keeps its fixed sizes on purpose — its rows are computed from
    /// the height they have to share (L-16).
    @ScaledMetric(relativeTo: .body) private var typeScale: CGFloat = 1
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Past the accessibility sizes a lane no longer fits on one line, and
    /// simply scaling the type squeezed the name column until it truncated to
    /// "Sara Leb…" — turning the one setting meant to help someone read a name
    /// into the thing that hid it. The row reflows instead: lane and name get
    /// the full width, club and seed time drop underneath.
    private var stacked: Bool { typeSize.isAccessibilitySize }

    private var laneColumn: CGFloat { 22 * typeScale }

    var body: some View {
        // Tighter than the 6pt the smaller type needed: at 17pt the rows are
        // taller, so the same gap read as a gappy list rather than a heat.
        VStack(alignment: .leading, spacing: 3) {
            header
            ForEach(heat.lanes, id: \.lane) { lane in
                laneRow(lane)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(heat.stripe % 2 == 0 ? palette.rowEven : palette.rowOdd)   // S-04
        .overlay(alignment: .leading) {
            if heat.isCurrent { palette.time.frame(width: 4) }   // S-05
        }
    }

    @ViewBuilder private var header: some View {
        let time = heat.heat.time.isEmpty ? nil :
            Text(heat.heat.time).font(faces.timing(13 * typeScale)).foregroundStyle(palette.scheduleTime)
        let eventHeat = Text("\(labels["event"] ?? "") \(heat.heat.event) \u{2014} \(labels["heat"] ?? "") \(heat.heat.heat)")
            .font(faces.text(17 * typeScale, weight: .semibold)).foregroundStyle(palette.scheduleEvent)
        let name = eventName.isEmpty ? nil :
            Text(eventName).font(faces.text(17 * typeScale)).foregroundStyle(palette.rowText)

        // A header, so the VoiceOver rotor can jump heat to heat rather than
        // walking every lane — on the screen whose whole purpose is finding one
        // swimmer among several hundred.
        Group {
            if stacked {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        time
                        eventHeat
                        Spacer(minLength: 0)
                    }
                    name?.fixedSize(horizontal: false, vertical: true)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    time
                    eventHeat
                    name?.fitOneLine(minimumScale: 0.7)
                    Spacer()
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// The seed time in a column of its own, as wide as the widest one on screen
    /// and with its value at the trailing edge.
    ///
    /// The club and the time used to be packed against the right edge at their
    /// natural widths, so the club's position followed the width of the time
    /// beside it and the codes zig-zagged down the card. A lane with no time
    /// reads "NT", six characters narrower than "1:04.219", which threw its
    /// club that much further out; but "57.40" against "1:04.219" was already
    /// enough to break the column on any ordinary heat. Sizing from a hidden
    /// copy of the longest string rather than a constant keeps the column as
    /// narrow as the meet actually needs — a schedule of "NT" reserves two
    /// characters, not eight.
    ///
    /// Never wrapped: a seed time broken across two lines reads as two times.
    ///
    /// 14pt, the club's size, because the two were one size in the stylesheet
    /// this screen came from (12 each) and the pass that lifted the row to
    /// platform body sizes moved the club and missed the time.
    @ViewBuilder private func seedColumn(_ lane: ScheduleLane) -> some View {
        if !seedTemplate.isEmpty {
            let font = faces.timing(14 * typeScale)
            Text(seedTemplate)
                .font(font)
                .lineLimit(1)
                .fixedSize()
                // Out of the drawing and out of the accessibility tree: it is
                // a ruler, and VoiceOver reading every lane's column width
                // before its time would be worse than the misalignment.
                .hidden()
                .overlay(alignment: .trailing) {
                    Text(lane.seedTime)
                        .font(font)
                        .foregroundStyle(palette.scheduleTime)
                        .lineLimit(1)
                        .fixedSize()
                }
        }
    }

    @ViewBuilder private func laneRow(_ lane: ScheduleLane) -> some View {
        let number = Text(String(lane.lane)).font(faces.text(15 * typeScale))
            .foregroundStyle(palette.thText).frame(width: laneColumn, alignment: .trailing)
        let name = Text(ScheduleView.displayName(lane)).font(faces.text(17 * typeScale))
            .foregroundStyle(palette.scheduleName)
        let club = lane.club.isEmpty ? nil :
            Text(lane.club).font(faces.text(14 * typeScale)).foregroundStyle(palette.scheduleClub)
        let seed = seedColumn(lane)

        if stacked {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    number
                    // Wraps rather than shrinking: at these sizes the name is
                    // the whole point of the row.
                    name.lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Color.clear.frame(width: laneColumn, height: 0)
                    // A lower floor than the one-line layout uses: the seed
                    // time never shrinks, so at these sizes a four-letter club
                    // was ellipsised to "RI…" rather than simply set smaller.
                    // A club code is two to five capitals; half size still
                    // reads, a missing half does not.
                    club?.fitOneLine(minimumScale: 0.5)
                    Spacer(minLength: 6)
                    seed
                }
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                number
                name.fitOneLine()
                Spacer(minLength: 6)
                club?.fitOneLine(minimumScale: 0.7)
                seed
            }
        }
    }
}
