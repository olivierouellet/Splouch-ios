import SwiftUI
import SplouchCore

/// S-08 to S-19: the full-screen filter sheet. Its words are the server's
/// (`mobile`, T-05); only the Done button is the platform's.
struct FilterSheet: View {
    @Bindable var ctx: MeetContext
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var suggestions: [Suggestion] = []
    @State private var confirmReset = false

    private var strings: StringTable { ctx.strings }
    /// Searching replaces the sheet's contents, the way a search over a list
    /// does everywhere else on the platform.
    private var searching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            List {
                if searching {
                    Section {
                        if suggestions.isEmpty {
                            Text(strings.mobile("no_search_results")).foregroundStyle(.secondary)   // S-19
                        }
                        ForEach(Array(suggestions.enumerated()), id: \.offset) { _, s in
                            suggestionRow(s)
                        }
                    }
                } else {
                    Section {
                        if ctx.filter.isFiltering {
                            chips
                        } else {
                            Text(strings.mobile("no_filters")).foregroundStyle(.secondary)
                        }
                    }
                    Section {
                        Toggle(strings.mobile("show_all_heats"), isOn: $ctx.filter.showAllHeats)   // S-16
                        Toggle(strings.mobile("upcoming_only"), isOn: $ctx.filter.upcomingOnly)   // S-17
                        Button(role: .destructive) { confirmReset = true } label: {
                            Text(strings.mobile("reset_filters"))
                        }
                        .disabled(ctx.filter == ScheduleFilter())
                    }
                }
            }
            // The platform's search field, which brings its own Cancel, clear
            // button and keyboard handling.
            .searchable(text: $query, placement: Self.searchPlacement, prompt: strings.mobile("search_placeholder"))
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.never)   // a name search, folded either way
            #endif
            // S-09: no debounce — the old ~220ms wait spared the server, and
            // over a local index it is only lag.
            .onChange(of: query) { _, q in suggestions = ctx.suggestions.search(q) }
            // S-21: a new start list rebuilt the index under us.
            .onChange(of: ctx.schedule) { _, _ in suggestions = ctx.suggestions.search(query) }
            .navigationTitle(strings.mobile("filter"))
            .toolbar {
                // It only dismisses: every control here already writes straight
                // to `ctx.filter`, so the schedule is filtered before this is
                // tapped.
                ToolbarItem(placement: .confirmationAction) {
                    Button(Native.done) { dismiss() }
                }
            }
            .sensoryFeedback(.impact(weight: .light), trigger: ctx.filter.terms.count)
            // S-18: the dialog brings the platform's own Cancel.
            .confirmationDialog(strings.mobile("reset_confirm"), isPresented: $confirmReset, titleVisibility: .visible) {
                Button(strings.mobile("reset_filters"), role: .destructive) { ctx.filter.reset() }
            }
        }
    }

    /// Pinned open: this sheet is a filter, so hiding the field until the list
    /// is dragged down would hide the point of the screen.
    private static var searchPlacement: SearchFieldPlacement {
        #if os(iOS)
        .navigationBarDrawer(displayMode: .always)
        #else
        .automatic
        #endif
    }

    // S-10: type, name, club; already-added ones are marked and inert.
    //
    // `.buttonStyle(.plain)` for the same reason ServerSheet's rows use it:
    // inside a Button in a List the default style makes `.primary` and
    // `.secondary` levels of the accent rather than absolute colours, so a
    // swimmer's name came out blue — reading as a link rather than a result.
    private func suggestionRow(_ s: Suggestion) -> some View {
        let term = s.term
        let added = ctx.filter.contains(term)
        return Button {
            ctx.filter.add(term)
            query = ""
            suggestions = []
        } label: {
            HStack {
                Image(systemName: term.kind == .club ? "building.2" : "person")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading) {
                    Text(s.name).foregroundStyle(.primary)
                    Text([strings.mobile(term.kind == .club ? "club" : "swimmer"), term.kind == .swimmer ? s.club : ""]
                        .filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                if added { Image(systemName: "checkmark").foregroundStyle(.secondary) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(added)
    }

    // S-11
    private var chips: some View {
        FlowLayout(spacing: 8) {
            ForEach(ctx.filter.terms, id: \.self) { term in
                HStack(spacing: 4) {
                    Image(systemName: term.kind == .club ? "building.2" : "person").font(.caption)
                    Text(term.name).font(.subheadline)
                    Button { ctx.filter.remove(term) } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(.quaternary, in: Capsule())
            }
        }
        .padding(.vertical, 4)
    }
}

/// Wraps chips onto as many lines as needed.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
