import SwiftUI
import SplouchCore

/// The Schedule tab (app.md §5.1).
struct ScheduleTab: View {
    let ctx: MeetContext
    @Environment(\.palette) private var palette
    @Environment(\.faces) private var faces
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
                        emptyState(ctx.strings.mobile(ctx.kind == .pi ? "no_meet" : "no_schedule"))
                    } else if ctx.schedule == nil {
                        if ctx.scheduleFailed { emptyState(Native.serverUnreachable) } else { ProgressView().padding(40) }
                    } else if visible.isEmpty {
                        // S-19: no swimmer matches these filters.
                        emptyState(ctx.strings.mobile(ctx.filter.upcomingOnly && !ctx.filter.isFiltering ? "no_upcoming" : "no_matches"))
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

    private func emptyState(_ text: String) -> some View {
        Text(text).font(faces.text(15)).foregroundStyle(palette.thText).padding(40)
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
    @Environment(\.sideInset) private var sideInset

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if !heat.heat.time.isEmpty {
                    Text(heat.heat.time).font(faces.timing(13)).foregroundStyle(palette.scheduleTime)
                }
                Text("\(labels["event"] ?? "") \(heat.heat.event) \u{2014} \(labels["heat"] ?? "") \(heat.heat.heat)")
                    .font(faces.text(14, weight: .semibold)).foregroundStyle(palette.rowText)
                Spacer()
            }
            if !eventName.isEmpty {
                Text(eventName).font(faces.text(13)).foregroundStyle(palette.scheduleEvent).fitOneLine(minimumScale: 0.7)
            }
            ForEach(heat.lanes, id: \.lane) { lane in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(String(lane.lane)).font(faces.text(13)).foregroundStyle(palette.thText).frame(width: 22, alignment: .trailing)
                    Text(ScheduleView.displayName(lane)).font(faces.text(14)).foregroundStyle(palette.scheduleName).fitOneLine()
                    Spacer(minLength: 6)
                    if !lane.club.isEmpty {
                        Text(lane.club).font(faces.text(12)).foregroundStyle(palette.scheduleClub).fitOneLine(minimumScale: 0.7)
                    }
                    if !lane.seedTime.isEmpty {
                        Text(lane.seedTime).font(faces.timing(12)).foregroundStyle(palette.scheduleTime)
                    }
                }
            }
        }
        .padding(12)
        .padding(.horizontal, sideInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(heat.stripe % 2 == 0 ? palette.rowEven : palette.rowOdd)   // S-04
        .overlay(alignment: .leading) {
            if heat.isCurrent { palette.time.frame(width: 4) }   // S-05
        }
    }
}
