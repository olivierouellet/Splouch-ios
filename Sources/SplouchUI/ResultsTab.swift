import SwiftUI
import SplouchCore

/// The Results tab (app.md §4).
struct ResultsTab: View {
    let ctx: MeetContext
    let isLandscape: Bool
    @Environment(\.palette) private var palette
    @Environment(\.faces) private var faces

    var body: some View {
        let n = ctx.settings.numLanes
        let snapshot = ctx.session.results
        let rows = snapshot.map { ResultsBoard.rows($0, numLanes: n) } ?? ResultsBoard.empty(numLanes: n)
        VStack(spacing: 0) {
            BoardHeader(event: snapshot?.event ?? "", heat: snapshot?.heat ?? "",
                        eventName: snapshot.map { ctx.eventName($0.eventName, parts: $0.eventNameParts) } ?? "",
                        labels: ctx.labels)
            ScrollView {
                VStack(spacing: 0) {
                    BoardTable(rows: rows.map(BoardRow.init), columns: Columns(ctx.settings), labels: ctx.labels,
                               isLandscape: isLandscape)
                        .frame(minHeight: isLandscape ? 0 : CGFloat(n) * 52)
                    if snapshot == nil {
                        // R-01: below the empty grid, wherever there is room.
                        Text(ctx.strings.mobile("waiting_results"))
                            .font(faces.text(15))
                            .foregroundStyle(palette.thText)
                            .padding(.vertical, 24)
                    }
                }
            }
            .refreshable { await ctx.refresh() }
        }
        .onAppear { ctx.session.resultsTabShown() }   // R-10
    }
}
