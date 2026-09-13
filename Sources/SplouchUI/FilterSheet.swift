import SwiftUI
import SplouchCore

/// S-08 to S-19: the full-screen filter sheet. Its words are the server's
/// (`mobile`, T-05); only the Done button is the platform's.
struct FilterSheet: View {
    @Bindable var ctx: MeetContext
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var suggestions: [SearchSuggestion] = []
    @State private var searched = false
    @State private var confirmReset = false
    @State private var searchTask: Task<Void, Never>?

    private var strings: StringTable { ctx.strings }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField(strings.mobile("search_placeholder"), text: $query)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)   // a name search, sent as typed
                        #endif
                        .onChange(of: query) { _, q in search(q) }
                    if searched, suggestions.isEmpty, !query.isEmpty {
                        Text(strings.mobile("no_search_results")).foregroundStyle(.secondary)   // S-19
                    }
                    ForEach(Array(suggestions.enumerated()), id: \.offset) { _, s in
                        suggestionRow(s)
                    }
                }
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
            .navigationTitle(strings.mobile("filter"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { doneButton }
            }
            // S-18: the dialog brings the platform's own Cancel.
            .confirmationDialog(strings.mobile("reset_confirm"), isPresented: $confirmReset, titleVisibility: .visible) {
                Button(strings.mobile("reset_filters"), role: .destructive) { ctx.filter.reset() }
            }
        }
    }

    /// The platform's own Done where it offers one, ours below that.
    @ViewBuilder private var doneButton: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            Button(role: .close) { dismiss() }
        } else {
            Button(Native.done) { dismiss() }
        }
    }

    // S-10: type, name, club; already-added ones are marked and inert.
    private func suggestionRow(_ s: SearchSuggestion) -> some View {
        let term = FilterTerm(kind: s.type == "club" ? .club : .swimmer, name: s.name)
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
        }
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

    // S-09: debounced ~220ms.
    private func search(_ q: String) {
        searchTask?.cancel()
        let trimmed = q.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { suggestions = []; searched = false; return }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            let result = (try? await ctx.api.searchSuggestions(meetID: ctx.meetID, query: trimmed)) ?? []
            guard !Task.isCancelled else { return }
            suggestions = result
            searched = true
        }
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
