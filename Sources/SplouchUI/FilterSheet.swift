import SwiftUI
import SplouchCore

/// S-08 to S-19: the filter sheet. Its words are the server's (`mobile`, T-05);
/// only the confirming checkmark is the platform's.
struct FilterSheet: View {
    @Bindable var ctx: MeetContext
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var suggestions: [Suggestion] = []
    @State private var confirmReset = false
    /// Searching is a mode, and the mode begins at the tap — not at the first
    /// letter. Everything below the field stands down while it is on.
    @FocusState private var searching: Bool

    private var strings: StringTable { ctx.strings }
    private var typing: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            List {
                // The field is a row in the sheet, not `.searchable`.
                //
                // `.searchable` is built to filter the content on screen, and
                // this field does not: it adds a term to a list. So tapping it
                // pushed the system's search presentation — the title and the
                // confirm button swapped for a cancel X — over a body that had
                // nothing new to show, which read as a second window drawn to
                // look like the first. The job here is entry, the way Mail
                // takes a recipient.
                Section {
                    entryField
                    if typing {
                        if suggestions.isEmpty {
                            Text(strings.mobile("no_search_results")).foregroundStyle(.secondary)   // S-19
                        }
                        ForEach(Array(suggestions.enumerated()), id: \.offset) { _, s in
                            suggestionRow(s)
                        }
                    }
                }

                // Tapping the field used to push these down the screen a row at
                // a time as results arrived. They step out of the way instead,
                // so the results open into the space they leave rather than
                // shoving them under the fold.
                if !searching {
                    Section {
                        if ctx.filter.isFiltering {
                            chips
                        } else {
                            Text(strings.mobile("no_filters")).foregroundStyle(.secondary)
                        }
                    }
                    Section {
                        // S-16, S-17. Two independent switches, so not a
                        // segmented control — but `.button` toggle style puts
                        // them on one row instead of two full-width ones, and
                        // FlowLayout wraps rather than clips a long translation.
                        FlowLayout(spacing: 8) {
                            pill(strings.mobile("show_all_heats"), isOn: $ctx.filter.showAllHeats)
                            pill(strings.mobile("upcoming_only"), isOn: $ctx.filter.upcomingOnly)
                        }
                        .padding(.vertical, 4)
                    }
                    Section {
                        Button(role: .destructive) { confirmReset = true } label: {
                            Text(strings.mobile("reset_filters"))
                                .frame(maxWidth: .infinity)
                        }
                        .disabled(ctx.filter == ScheduleFilter())
                    }
                }
            }
            .animation(.easeInOut(duration: 0.25), value: searching)
            .navigationTitle(strings.mobile("filter"))
            #if os(iOS)
            // Inline, so the title shares the bar with the checkmark rather than
            // taking a line of its own above it.
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                // A checkmark, the way Settings confirms a choice. It only
                // dismisses: every control here already writes straight to
                // `ctx.filter`, so the schedule is filtered before this is
                // tapped and the mark confirms what is already true.
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: {
                        Label(Native.done, systemImage: "checkmark")
                            .labelStyle(.iconOnly)
                    }
                }
            }
            .sensoryFeedback(.impact(weight: .light), trigger: ctx.filter.terms.count)
            // S-18: the dialog brings the platform's own Cancel.
            .confirmationDialog(strings.mobile("reset_confirm"), isPresented: $confirmReset, titleVisibility: .visible) {
                Button(strings.mobile("reset_filters"), role: .destructive) { ctx.filter.reset() }
            }
        }
    }

    private var entryField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(strings.mobile("search_placeholder"), text: $query)
                .focused($searching)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)   // a name search, folded either way
                .submitLabel(.done)
                #endif
                .onSubmit { searching = false }
                // S-09: no debounce — the old ~220ms wait spared the server, and
                // over a local index it is only lag.
                .onChange(of: query) { _, q in suggestions = ctx.suggestions.search(q) }
                // S-21: a new start list rebuilt the index under us.
                .onChange(of: ctx.schedule) { _, _ in suggestions = ctx.suggestions.search(query) }
            // Shown for the whole of the mode, not only once something is
            // typed: with the rest of the sheet stood down it is the way back.
            if searching || typing {
                Button {
                    query = ""
                    suggestions = []
                    searching = false
                } label: {
                    // 17pt of glyph, 44pt of target: the HIG minimum, which an
                    // icon button sized to its symbol never meets.
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Native.cancel)
            }
        }
    }

    /// A switch drawn as a capsule. Still a Toggle, so VoiceOver announces it
    /// as one rather than as a button.
    ///
    /// On is filled and off is outlined, rather than leaving both to the
    /// `.bordered` default — that draws the label in the accent either way, so
    /// a switch that was off still read as on.
    @ViewBuilder private func pill(_ title: String, isOn: Binding<Bool>) -> some View {
        let toggle = Toggle(title, isOn: isOn)
            .toggleStyle(.button)
            .buttonBorderShape(.capsule)
            .font(.subheadline)
        if isOn.wrappedValue {
            toggle.buttonStyle(.borderedProminent)
        } else {
            toggle.buttonStyle(.bordered).tint(Color.secondary)
        }
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
            // Leaving the mode is the confirmation: the sheet comes back and
            // the new token is there in it.
            searching = false
        } label: {
            HStack {
                Image(systemName: term.kind == .club ? "building.2" : "person")
                    .foregroundStyle(.secondary)
                    // The line under the name already says swimmer or club.
                    .accessibilityHidden(true)
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
                        .accessibilityHidden(true)
                    Text(term.name).font(.subheadline)
                    Button { ctx.filter.remove(term) } label: {
                        // The target is 44pt and the negative padding takes it
                        // back out of the layout, so the chip stays chip-sized
                        // while the tap area is the one the HIG asks for.
                        // Chips sit shoulder to shoulder here, so a 17pt target
                        // meant removing the wrong swimmer.
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                            .padding(-6)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(Native.remove), \(term.name)")
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
