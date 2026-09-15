import SwiftUI
import SplouchCore

/// The Results tab (app.md §4).
struct ResultsTab: View {
    let ctx: MeetContext
    let isLandscape: Bool

    var body: some View {
        let n = ctx.settings.numLanes
        let snapshot = ctx.session.results
        VStack(spacing: 0) {
            // Landscape hands this to the navigation bar instead (MeetShell).
            if !isLandscape {
                BoardHeader(event: snapshot?.event ?? "", heat: snapshot?.heat ?? "",
                            eventName: snapshot.map { ctx.eventName($0.eventName, parts: $0.eventNameParts) } ?? "",
                            labels: ctx.labels)
            }
            GeometryReader { geo in
                ScrollView {
                    if let snapshot {
                        BoardTable(rows: ResultsBoard.rows(snapshot, numLanes: n).map(BoardRow.init),
                                   columns: Columns(ctx.settings), labels: ctx.labels,
                                   isLandscape: isLandscape,
                                   height: max(0, geo.size.height - BoardTable.bottomGap))
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
            }
        }
        .onAppear { ctx.session.resultsTabShown() }   // R-10
    }
}
