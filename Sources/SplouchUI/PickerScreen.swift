import SplouchCore
import SwiftUI

/// The meet picker (app.md §1). Language is the device's, not a meet's. Its
/// chrome is the server's words (`mobile`, T-05); settings (P-19) and the
/// connection error are the app's.
struct PickerScreen: View {
    let app: AppModel
    let opening: Bool
    let open: (MeetSummary) async -> Void
    let openPi: () async -> Void

    /// P-19.
    @State private var showSettings = false
    /// P-06's tap.
    @State private var showDisclaimer = false
    /// P-21.
    @State private var showFilter = false
    /// P-17. State of the picker, which is the root of the navigation stack, so
    /// it outlives a pushed meet (A-02) and a pull-to-refresh (P-09) and is
    /// gone on a cold launch — what the web keeps in `sessionStorage`.
    @State private var query = ""
    /// X-10: where VoiceOver goes when a sheet closes — the control that
    /// opened it.
    @AccessibilityFocusState private var focus: Opener?

    /// Landscape on a phone is a compact height, which is the one axis the
    /// branding has to give ground on.
    #if os(iOS)
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    private var shortScreen: Bool { verticalSizeClass == .compact }
    #else
    private var shortScreen: Bool { false }
    #endif

    private var strings: StringTable { app.strings }
    private var picker: PickerConfig? { app.picker }

    var body: some View {
        // A grouped list rather than a ScrollView of hand-drawn cards. The rows
        // were `RoundedRectangle.stroke(border)` — a `border: 1px solid #2e2e2e`
        // carried over from `picker.html` — around content the platform draws
        // better itself: cell backgrounds, separators, press states, and the
        // insets every other iOS list uses.
        List {
            Section {
                serverLine
                branding
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            // The branding has no cell to separate from what follows, so the
            // grouped list's full section gap only pushes the disclaimer away.
            .compactSectionSpacing()

            meets
        }
        .groupedList()
        // The grouped list's own top inset sits over a first section with no
        // header: under the toolbar it read as dead space above the logo, in
        // portrait as much as in landscape. The branding's padding is the gap.
        .contentMargins(.top, 0, for: .scrollContent)
        .refreshable { await app.load() }  // P-09
        .meetSearch(shown: searchShown, text: $query, prompt: served("meet_search"))
        .overlay { if app.loading && app.meets.isEmpty { ProgressView() } }
        .toolbar { toolbar }
        .sheet(isPresented: $showSettings) { SettingsSheet(app: app) }
        .sheet(isPresented: $showFilter) { MeetFilterSheet(app: app) }
        .onChange(of: showSettings) { _, shown in if !shown { refocus(.settings) } }
        .onChange(of: showFilter) { _, shown in if !shown { refocus(.filter) } }
        .onChange(of: showDisclaimer) { _, shown in if !shown { refocus(.disclaimer) } }
        // P-20, first launch: only once the server has answered, and not over
        // settings opened while it was still offline.
        .introCover(
            isPresented: Binding(
                get: { app.introDue && !showSettings },
                set: { if !$0 { app.finishIntro() } }),
            app: app)
        // The greys are the system's grouped-background ones rather than the
        // stylesheet's hex, so they track Increase Contrast, match every other
        // app on the device, and follow whichever scheme P-15 resolves to —
        // which SplouchRootView owns for the whole window.
    }

    /// A picker string: `GET /picker/config` first, then the `mobile` table an
    /// older server that predates the key still falls back through (T-10).
    /// Empty counts as absent, as it does in `StringTable`.
    private func served(_ key: String) -> String {
        if let v = picker?.strings[key], !v.isEmpty { return v }
        return strings.mobile(key)
    }

    /// P-17: under three meets there is no field, and nothing is filtered — a
    /// query typed before a refresh shrank the list waits for it to grow back,
    /// as the web's does.
    private var searchShown: Bool { MeetSearch.isShown(meetCount: app.meets.count) }

    /// P-21: offered with P-17's field, and whenever a filter is standing, so a
    /// list it shrank always shows the control that can widen it again. A Pi
    /// has no list to filter.
    private var filter: MeetFilter { app.preferences.meetFilter }
    private var filterShown: Bool { !app.isPi && !app.unreachable && (searchShown || filter.isActive) }
    /// P-21 before P-17: the query searches what the filter leaves.
    private var filteredMeets: [MeetSummary] { filter.apply(app.meets) }
    private var shownMeets: [MeetSummary] {
        searchShown ? MeetSearch.filter(filteredMeets, query: query, locale: app.locale) : filteredMeets
    }

    @ViewBuilder private var meets: some View {
        if app.unreachable {
            Section {
                // A connection error is about the device, so it is native (T-05).
                Unavailable(
                    text: Native.serverUnreachable, symbol: "wifi.exclamationmark",
                    actionLabel: Native.retry, fillsContainer: false
                ) { Task { await app.load() } }
            } header: {
                disclaimerLine
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } else if app.isPi {
            Section {
                Button {
                    Task { await openPi() }
                } label: {
                    Label(Native.openBoard, systemImage: "sportscourt")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .disabled(opening)
            } header: {
                disclaimerLine
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } else if app.meets.isEmpty, !app.loading {
            Section {
                // P-04 on the platform's empty state. The words stay the
                // server's (T-05); only the presentation is the system's.
                Unavailable(
                    text: served("no_meets"),
                    symbol: "calendar.badge.exclamationmark", fillsContainer: false)
            } header: {
                disclaimerLine
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } else if filteredMeets.isEmpty {
            Section {
                // P-21's own empty state: the server has meets, the filter hid
                // them all. Not P-04, and not P-17's — no query is to blame.
                Unavailable(
                    text: Native.filterHidesAll, symbol: "line.3.horizontal.decrease.circle",
                    actionLabel: Native.filterClear, fillsContainer: false
                ) { app.setMeetFilter(MeetFilter()) }
            } header: {
                disclaimerLine
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } else if shownMeets.isEmpty, !app.meets.isEmpty {
            Section {
                // P-17's own empty state: the search hid every meet. Not P-04,
                // which says the server has none at all.
                Unavailable(text: served("no_meets_match"), symbol: "magnifyingglass", fillsContainer: false)
            } header: {
                disclaimerLine
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } else {
            // P-01: a section per day, headed by it. P-06's line heads the
            // first, above the day; P-21's count ends the last.
            let days = MeetDay.group(shownMeets)
            ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                Section {
                    ForEach(day.meets) { meet in
                        Button {
                            Task { await open(meet) }
                        } label: {
                            // P-18: past ten meets every row is compact and no
                            // picker image is asked for — `pickerImageURL` is nil
                            // for all of them.
                            MeetCard(
                                meet: meet,
                                imageURL: app.pickerImageURL(for: meet),
                                compact: app.listIsCompact,
                                filter: filter,
                                unnamed: served("unnamed_meet"),
                                offline: strings.mobile("offline"),
                                testBadge: served("test_meet"))
                        }
                        .buttonStyle(CardButtonStyle())
                        .disabled(opening)
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 8) {
                        if index == 0 { disclaimerLine }
                        Text(day.heading(locale: app.locale) ?? (day.date.isEmpty ? served("date_unknown") : day.date))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .textCase(nil)
                            .accessibilityAddTraits(.isHeader)
                    }
                } footer: {
                    if index == days.count - 1 { hiddenByFilter }
                }
            }
        }
    }

    /// P-21: at the end of the list, how many meets the filter keeps out of it,
    /// so a short list is never taken for the whole server.
    @ViewBuilder private var hiddenByFilter: some View {
        let hidden = app.meets.count - filteredMeets.count
        if hidden > 0 {
            VStack(spacing: 4) {
                Label(Native.filterHidden(hidden), systemImage: "line.3.horizontal.decrease.circle")
                    .foregroundStyle(.secondary)
                Button(Native.filterClear) { app.setMeetFilter(MeetFilter()) }
                    .frame(minHeight: 44)  // X-05
            }
            .font(.footnote)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
        }
    }

    /// P-06: one quiet line over the meets, always there once the server has
    /// sent its words, and never closable — so no X, no pill, no stored fold.
    /// The section header rather than a row: above the meets whatever the
    /// list holds, and above P-17's results too. Tap for the full text — a
    /// half-height sheet on a phone, a popover on iPad (the system adapts a
    /// popover to a sheet in a compact width).
    @ViewBuilder private var disclaimerLine: some View {
        if let short = app.disclaimerShort, let full = app.disclaimer {
            Button {
                showDisclaimer = true
            } label: {
                // Not a `Label`'s list style: in a header that takes the row's
                // icon column. The hourglass is the same on every client.
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Image(systemName: "hourglass").accessibilityHidden(true)
                    Text(short)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .textCase(nil)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 44)  // X-05
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // The 44pt target already spaces the line from the logo; the
            // header's own vertical inset only doubled that gap.
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            .accessibilityFocused($focus, equals: .disclaimer)
            .popover(isPresented: $showDisclaimer) {
                DisclaimerSheet(title: short, text: full)
            }
        }
    }

    /// P-11: the meet list names its server only when it is not the default
    /// (`AppModel.namesServer`) — a spectator who switched and forgot sees why
    /// the meets changed; on the default there is nothing to explain. A meet
    /// does the same (MeetShell.subtitle). By its address rather than its name:
    /// the address is what a spectator can check against a poster or a URL bar.
    /// P-14: the contract notice sits beside it, or alone on the default, never
    /// a gate.
    @ViewBuilder private var serverLine: some View {
        let name = app.namesServer ? app.server.display : nil
        let parts = [name, app.contractNotice].compactMap { $0 }
        if !parts.isEmpty {
            // An HStack rather than a Label: in a list row a Label's icon takes
            // the row's leading column, which left a wide gap before the address.
            HStack(spacing: 4) {
                if name != nil { Image(systemName: "server.rack") }
                Text(parts.joined(separator: " \u{00B7} "))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
        }
    }

    // P-05
    //
    // In landscape this block was taking the top third of the screen with the
    // logo floating in the middle of it and the meet list pushed to the bottom
    // edge. Two reasons, both fixed here: an operator who sets a logo and no
    // title still got an empty `.title2` line holding its full height, and the
    // 80pt logo box plus its padding is sized for the axis that has room.
    @ViewBuilder private var branding: some View {
        let title = picker?.title ?? app.serverName
        let above = picker?.logoAbove ?? false
        let logo =
            (picker?.hasLogo ?? false)
            ? AsyncImage(url: app.api.pickerLogoURL()) {
                $0.resizable().scaledToFit()
            } placeholder: {
                EmptyView()
            }
            .frame(maxHeight: shortScreen ? 44 : 80) : nil
        VStack(spacing: shortScreen ? 4 : 8) {
            if above { logo }
            if !title.isEmpty {
                Text(title)
                    .font(.title2.weight(.regular))
                    .textCase(.uppercase)
                    .tracking(1.5)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if !above { logo }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, shortScreen ? 2 : 8)
        // Nothing under the logo but the notices, which read as its caption:
        // the row's bottom inset is what kept them a screen-third away.
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 0, trailing: 16))
    }

    /// X-10: the control comes back on the next pass, after the sheet is gone.
    private func refocus(_ target: Opener) {
        Task { @MainActor in
            await Task.yield()
            focus = target
        }
    }

    /// P-19: a gear, not ☰ or ⋯ — settings now hold a toggle, its note and
    /// links, which a menu renders badly.
    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        // P-21: filled while a filter stands, the system's mark for "on".
        if filterShown {
            ToolbarItem(placement: .automatic) {
                Button {
                    showFilter = true
                } label: {
                    Label(
                        Native.meetFilter,
                        systemImage: filter.isActive
                            ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
                .accessibilityValue(filter.isActive ? Native.filterHidden(app.meets.count - filteredMeets.count) : "")
                .accessibilityFocused($focus, equals: .filter)
            }
        }
        ToolbarItem(placement: .automatic) {
            Button {
                showSettings = true
            } label: {
                Label(Native.settings, systemImage: "gearshape")
            }
            .accessibilityFocused($focus, equals: .settings)
        }
    }
}

/// X-10: the controls on the picker that open a sheet.
private enum Opener: Hashable {
    case settings
    case disclaimer
    case filter
}

extension View {
    /// P-17 on the platform's own search field. In the bar's drawer on iOS 17
    /// to 25, above the list; iOS 26 moves it to a bar at the bottom of an
    /// iPhone screen, which is the system's place for search now and a
    /// departure from the contract's "above the cards" (parity.md P-17). Its
    /// Search key dismisses the keyboard and leaves the filter standing. The
    /// prompt is also what VoiceOver reads the field as.
    @ViewBuilder fileprivate func meetSearch(shown: Bool, text: Binding<String>, prompt: String) -> some View {
        if shown {
            #if os(iOS)
            Group {
                // On iOS 26 the drawer placement was the bottom bar on a cold
                // launch and gone after a pushed meet's tab bar popped, then
                // back at the top; `.automatic` is the bottom bar throughout.
                if #available(iOS 26, *) {
                    self.searchable(text: text, placement: .automatic, prompt: Text(prompt))
                } else {
                    self.searchable(
                        text: text, placement: .navigationBarDrawer(displayMode: .always), prompt: Text(prompt))
                }
            }
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)  // folded either way
            #else
            self.searchable(text: text, prompt: Text(prompt))
            #endif
        } else {
            self
        }
    }

    /// `.insetGrouped` is iOS-only; on macOS the picker is checked for
    /// compilation, not looked at.
    @ViewBuilder fileprivate func groupedList() -> some View {
        #if os(iOS)
        self.listStyle(.insetGrouped)
        #else
        self.listStyle(.sidebar)
        #endif
    }

    @ViewBuilder fileprivate func compactSectionSpacing() -> some View {
        #if os(iOS)
        self.listSectionSpacing(.compact)
        #else
        self
        #endif
    }
}

/// P-01, P-02, P-03. One meet as a list row: no card, no border, no padding of
/// its own — the list draws all three. The name on two lines at most, then
/// city, state/province code and country code on one; the day is the
/// section's. `compact` is P-18's row: the name on one line, no image slot.
struct MeetCard: View {
    let meet: MeetSummary
    let imageURL: URL?
    var compact = false
    /// P-21's filter: a country or province it narrows to one is not repeated.
    var filter = MeetFilter()
    let unnamed: String
    /// The server's word for a retained meet with no relay (`mobile.offline`).
    var offline: String = ""
    /// P-22: the server's word for a test meet (`test_meet`), after its name.
    var testBadge: String = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false
    /// P-01: one height for every row — one line of name leaves it padding, a
    /// second takes it back. Scaled with the text, so large type still fits.
    @ScaledMetric(relativeTo: .headline) private var rowHeight: CGFloat = 72

    /// The one colour here that is the product rather than the chrome, so it is
    /// the only one not taken from the system palette.
    private static let liveGreen = Color(hex: "#4CAF50")

    var body: some View {
        HStack(spacing: 12) {
            // P-02: the live dot leads the row, ahead of the meet's image.
            liveDot
            // The slot is reserved whether or not the meet carries an image, so
            // titles line up down the list; a meet without one shows the same
            // empty tile the image shows while it loads. P-18's rows have none.
            if !compact {
                Group {
                    if let imageURL {
                        AsyncImage(url: imageURL) {
                            $0.resizable().scaledToFill()
                        } placeholder: {
                            placeholder
                        }
                    } else {
                        placeholder
                    }
                }
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            VStack(alignment: .leading, spacing: 4) {
                // Two lines, shrinking a little before the ellipsis. On one
                // line with a 0.5 floor a long name hit that floor in portrait —
                // half of `.headline`, about 8.5pt — because the row is narrow.
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(meet.name.isEmpty ? unnamed : meet.name)
                        .font(.headline)
                        .lineLimit(compact ? 1 : 2)
                        .minimumScaleFactor(0.8)
                        .fixedSize(horizontal: false, vertical: true)
                    if meet.test, !testBadge.isEmpty { TestBadge(text: testBadge) }
                }
                // P-01: `Montréal · QC · CA`, cut at the end.
                let place = meet.place(filter: filter) + (meet.offline ? [offline] : [])
                if !place.isEmpty {
                    Text(place.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(minHeight: compact ? nil : rowHeight)
            Spacer(minLength: 8)
            // The disclosure glyph at the weight and colour the system draws it,
            // since an async open cannot be a NavigationLink.
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                // Decoration: the row is already a button.
                .accessibilityHidden(true)
        }
        .opacity(meet.offline ? 0.75 : 1)
    }

    private var placeholder: some View { Color.secondary.opacity(0.15) }

    /// P-22: the web's `.test-badge` — small, bold, outlined in the accent
    /// colour. Never shrunk or cut: the name gives way to it.
    private struct TestBadge: View {
        let text: String
        var body: some View {
            Text(text)
                .font(.caption2.weight(.bold))
                .tracking(0.5)
                .foregroundStyle(.tint)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.tint, lineWidth: 1))
                .fixedSize()
                .layoutPriority(1)
        }
    }

    /// A live meet breathes; a retained one is a hollow ring and holds still.
    /// Both are the same 8pt frame and only `opacity`/`scaleEffect` move, so a
    /// pulsing dot never shifts the image or the text beside it.
    @ViewBuilder private var liveDot: some View {
        if meet.offline {
            Circle().strokeBorder(.secondary, lineWidth: 1).frame(width: 8, height: 8)
        } else {
            Circle()
                .fill(Self.liveGreen)
                .frame(width: 8, height: 8)
                .shadow(color: Self.liveGreen.opacity(0.7), radius: 3)
                .opacity(pulsing ? 1 : 0.45)
                .scaleEffect(pulsing ? 1 : 0.78)
                // Core Animation drives this, unlike the board's per-frame
                // TimelineView pulse (L-12) — that one has to start and stop
                // with a lane, this one runs for the life of the row.
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 0.85).repeatForever(autoreverses: true),
                    value: pulsing
                )
                .onAppear { pulsing = true }
        }
    }
}
