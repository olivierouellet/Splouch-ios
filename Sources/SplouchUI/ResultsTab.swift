import SwiftUI
import SplouchCore

/// The Results tab (app.md §4).
struct ResultsTab: View {
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
        let n = ctx.settings.numLanes
        let snapshot = ctx.session.results
        VStack(spacing: 0) {
            // The navigation bar hands this back when it is drawing it itself.
            if !headerInBar {
                BoardHeader(event: snapshot?.event ?? "", heat: snapshot?.heat ?? "",
                            eventName: snapshot.map { ctx.eventName($0.eventName, parts: $0.eventNameParts) } ?? "",
                            labels: ctx.labels)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerBand = $0 }
            }
            GeometryReader { geo in
                ScrollView {
                    if let snapshot {
                        BoardTable(rows: ResultsBoard.rows(snapshot, numLanes: n).map(BoardRow.init),
                                   columns: Columns(ctx.settings), labels: ctx.labels,
                                   isLandscape: isLandscape,
                                   height: BoardTable.tableHeight(in: geo))
                    } else {
                        // R-01: an empty lane grid here says nothing. Blank rows
                        // are meaningful on the Scoreboard, where a heat is live
                        // and they fill in (L-09); before the first snapshot they
                        // are only a table the web had to draw to occupy the page.
                        // The Schedule tab's empty state, said the same way.
                        Unavailable(text: ctx.strings.mobile("waiting_results"), symbol: "list.number")
                    }
                }
                .refreshable { await ctx.refresh() }
                .onPreferenceChange(LaneIdealKey.self) { laneIdeal = $0 }
                .preference(key: BoardNeedsBarKey.self, value: needsBar(in: geo))
            }
        }
        .onAppear { ctx.session.resultsTabShown() }   // R-10
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
