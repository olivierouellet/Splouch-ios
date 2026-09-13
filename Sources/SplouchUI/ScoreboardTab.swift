import SwiftUI
import SplouchCore

/// The live board (app.md §3).
struct ScoreboardTab: View {
    let ctx: MeetContext
    let isLandscape: Bool

    var body: some View {
        let board = ctx.session.scoreboard
        VStack(spacing: 0) {
            BoardHeader(event: board.currentEvent, heat: board.currentHeat,
                        eventName: ctx.eventName(board.eventName, parts: board.eventNameParts), labels: ctx.labels)
            // The table sits in a scroll view for pull-to-refresh (A-05); in
            // landscape it is given the whole height so the rows share it (L-16).
            GeometryReader { geo in
                ScrollView {
                    BoardTable(rows: (1...board.numLanes).map { BoardRow($0, board[lane: $0]) },
                               columns: Columns(ctx.settings), labels: ctx.labels,
                               isLandscape: isLandscape, height: geo.size.height)
                        .frame(minHeight: isLandscape ? nil : CGFloat(board.numLanes) * 52)
                }
                .refreshable { await ctx.refresh() }
            }
        }
        // L-12: the device ticks the clock at ~10Hz off a monotonic instant while
        // the tab is on screen; the task ends with the view, so a hidden tab
        // never accumulates ticks. L-14: reappearing refreshes at once.
        .task {
            ctx.session.tick()
            while !Task.isCancelled {
                try? await Task.sleep(for: RaceClock.tickInterval)
                ctx.session.tick()
            }
        }
        .onDisappear { ctx.session.suspend() }
    }
}
