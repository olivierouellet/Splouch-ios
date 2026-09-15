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
                            HeatCard(heat: v, labels: ctx.labels, eventName: ctx.eventName(v.heat.eventName, parts: v.heat.eventNameParts))
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
        VStack(alignment: .leading, spacing: 6) {
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
            .font(faces.text(14 * typeScale, weight: .semibold)).foregroundStyle(palette.scheduleEvent)
        let name = eventName.isEmpty ? nil :
            Text(eventName).font(faces.text(13 * typeScale)).foregroundStyle(palette.rowText)

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

    @ViewBuilder private func laneRow(_ lane: ScheduleLane) -> some View {
        let number = Text(String(lane.lane)).font(faces.text(13 * typeScale))
            .foregroundStyle(palette.thText).frame(width: laneColumn, alignment: .trailing)
        let name = Text(ScheduleView.displayName(lane)).font(faces.text(17 * typeScale))
            .foregroundStyle(palette.scheduleName)
        let club = lane.club.isEmpty ? nil :
            Text(lane.club).font(faces.text(17 * typeScale)).foregroundStyle(palette.scheduleClub)
        // Never wrapped: a seed time broken across two lines reads as two times.
        let seed = lane.seedTime.isEmpty ? nil :
            Text(lane.seedTime).font(faces.timing(12 * typeScale)).foregroundStyle(palette.scheduleTime)
                .lineLimit(1).fixedSize()

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
                    club?.fitOneLine(minimumScale: 0.7)
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
