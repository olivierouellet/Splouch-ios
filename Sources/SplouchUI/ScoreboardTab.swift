import SwiftUI
import SplouchCore

/// The live board (app.md §3).
struct ScoreboardTab: View {
    let ctx: MeetContext
    let isLandscape: Bool
    /// The navigation bar is drawing the EVENT / HEAT row instead of this tab.
    /// Always so in landscape; in portrait only when the lanes need the height
    /// (`MeetShell.crowdedPortrait`).
    let headerInBar: Bool
    /// What the board's own header row costs, measured while it is being drawn
    /// and remembered once it moves to the bar. A lane's natural height comes up
    /// from `BoardTable` the same way. Between them the tab can answer whether
    /// the lanes still fit underneath without a single number baked in.
    @State private var headerBand: CGFloat = 0
    @State private var laneIdeal: CGFloat = 0

    var body: some View {
        let board = ctx.session.scoreboard
        VStack(spacing: 0) {
            // The navigation bar hands this back when it is drawing it itself.
            if !headerInBar {
                BoardHeader(event: board.currentEvent, heat: board.currentHeat,
                            eventName: ctx.eventName(board.eventName, parts: board.eventNameParts), labels: ctx.labels)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerBand = $0 }
            }
            // The table sits in a scroll view for pull-to-refresh (A-05); in
            // landscape it is given the whole height so the rows share it (L-16).
            GeometryReader { geo in
                ScrollView {
                    BoardTable(rows: (1...board.numLanes).map { BoardRow($0, board[lane: $0]) },
                               columns: Columns(ctx.settings), labels: ctx.labels,
                               isLandscape: isLandscape,
                                   height: BoardTable.tableHeight(in: geo))
                }
                .refreshable { await ctx.refresh() }
                .onPreferenceChange(LaneIdealKey.self) { laneIdeal = $0 }
                .preference(key: BoardNeedsBarKey.self, value: needsBar(in: geo))
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

    /// Whether the lanes want the navigation bar to take the header row.
    ///
    /// Measured against the height they would have *with* the row in the bar,
    /// which is the same number either way the answer comes out — so moving the
    /// row cannot hand back the space that caused the move and flip it straight
    /// back. Nothing here is a constant: the lane's height and the header's band
    /// are both measured on the device in front of the reader.
    private func needsBar(in geo: GeometryProxy) -> Bool {
        guard !isLandscape, laneIdeal > 0, headerBand > 0 else { return false }
        let available = BoardTable.tableHeight(in: geo)
        let withTheBar = headerInBar ? available : available + headerBand
        return CGFloat(max(1, ctx.settings.numLanes)) * laneIdeal > withTheBar
    }
}
