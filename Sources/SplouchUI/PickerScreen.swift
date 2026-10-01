import SplouchCore
import SwiftUI

/// The meet picker (app.md §1). Language is the device's, not a meet's. Its
/// chrome and preference controls are the server's words (`mobile`, T-05);
/// the server menu and the connection error are the app's.
struct PickerScreen: View {
    let app: AppModel
    let opening: Bool
    let open: (MeetSummary) async -> Void
    let openPi: () async -> Void

    @State private var showServers = false
    @State private var showLanguages = false
    /// P-17. State of the picker, which is the root of the navigation stack, so
    /// it outlives a pushed meet (A-02) and a pull-to-refresh (P-09) and is
    /// gone on a cold launch — what the web keeps in `sessionStorage`.
    @State private var query = ""
    /// P-06, P-07: where VoiceOver goes after a fold or an unfold, since the
    /// control it was on has just been replaced.
    @AccessibilityFocusState private var noticeFocus: NoticeFocus?

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
            // grouped list's full section gap only pushes the notices away.
            .compactSectionSpacing()

            notices
            meets
        }
        .groupedList()
        // The grouped list's own top inset is generous, which is right in
        // portrait and costly on the axis that has no height to spare.
        .trimmedTop(shortScreen)
        .refreshable { await app.load() }  // P-09
        .meetSearch(shown: searchShown, text: $query, prompt: served("meet_search"))
        .overlay { if app.loading && app.meets.isEmpty { ProgressView() } }
        .toolbar { toolbar }
        .sheet(isPresented: $showServers) { ServerSheet(app: app) }
        .sheet(isPresented: $showLanguages) { LanguageSheet(app: app) }
        // The greys are the system's grouped-background ones rather than the
        // stylesheet's hex, so they track Increase Contrast, match every other
        // app on the device, and follow whichever scheme P-15 resolves to —
        // which SplouchRootView owns for the whole window.
    }

    /// A picker string: `GET /picker/config` first, then the `mobile` table an
    /// older server that predates the key still falls back through (T-10).
    private func served(_ key: String) -> String { picker?.strings[key] ?? strings.mobile(key) }

    /// P-17: under three meets there is no field, and nothing is filtered — a
    /// query typed before a refresh shrank the list waits for it to grow back,
    /// as the web's does.
    private var searchShown: Bool { MeetSearch.isShown(meetCount: app.meets.count) }
    private var shownMeets: [MeetSummary] {
        searchShown ? MeetSearch.filter(app.meets, query: query) : app.meets
    }

    @ViewBuilder private var meets: some View {
        if app.unreachable {
            Section {
                // A connection error is about the device, so it is native (T-05).
                Unavailable(
                    text: Native.serverUnreachable, symbol: "wifi.exclamationmark",
                    actionLabel: Native.retry, fillsContainer: false
                ) { Task { await app.load() } }
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
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } else if shownMeets.isEmpty, !app.meets.isEmpty {
            Section {
                // P-17's own empty state: the search hid every meet. Not P-04,
                // which says the server has none at all.
                Unavailable(text: served("no_meets_match"), symbol: "magnifyingglass", fillsContainer: false)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } else {
            Section {
                ForEach(shownMeets) { meet in
                    Button {
                        Task { await open(meet) }
                    } label: {
                        MeetCard(
                            meet: meet,
                            imageURL: meet.hasPickerImage ? app.api.pickerImageURL(meetID: meet.id) : nil,
                            unnamed: served("unnamed_meet"),
                            offline: strings.mobile("offline"))
                    }
                    .buttonStyle(CardButtonStyle())
                    .disabled(opening)
                }
            }
        }
    }

    /// P-11: the meet list always names its server — every card on it came
    /// from there, whichever one it is. Inside a meet only a non-default one is
    /// named (MeetShell.subtitle). By its address rather than its name: the
    /// address is what a spectator can check against a poster or a URL bar.
    /// P-14: the contract notice sits beside it, never a gate.
    private var serverLine: some View {
        let parts = [app.server.display, app.contractNotice].compactMap { $0 }
        // An HStack rather than a Label: in a list row a Label's icon takes the
        // row's leading column, which left a wide gap before the address.
        return HStack(spacing: 4) {
            Image(systemName: "server.rack")
            Text(parts.joined(separator: " \u{00B7} "))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
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

    // P-06, P-07: served, never compiled in, and above the list — under the
    // branding, before the meets — because under it a season of meets pushed
    // them out of sight. Each folds to a pill and never goes away.
    //
    // The two are not the same kind of text. P-06 is the only thing standing
    // between a live feed and a spectator taking it for a result, so it is at
    // full contrast; P-07 really is fine print, and stays secondary.
    @ViewBuilder private var notices: some View {
        let shown = PickerNotice.allCases.filter { app.noticeText($0) != nil }
        let open = shown.filter { !app.isFolded($0) }
        let folded = shown.filter { app.isFolded($0) }
        // Expanded, a notice has the row to itself.
        if !open.isEmpty {
            Section {
                ForEach(open, id: \.self) { expanded($0) }
            }
        }
        // Folded, the pills share one, centred, and stack when Dynamic Type
        // leaves no room for both side by side. A section of its own, so a
        // grouped block above it keeps its corners.
        if !folded.isEmpty {
            Section {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { pills(folded, oneLine: true) }
                    VStack(spacing: 8) { pills(folded, oneLine: false) }
                }
                .frame(maxWidth: .infinity)
                // No cell here, so no cell margins: the pills get the width.
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 0))
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    private func expanded(_ notice: PickerNotice) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(app.noticeText(notice) ?? "")
                .font(.subheadline)
                .foregroundStyle(notice == .results ? .primary : .secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                app.fold(notice)
                focus(.pill(notice))
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    // The HIG's 44pt target, with the glyph kept in the corner.
                    .frame(minWidth: 44, minHeight: 44, alignment: .topTrailing)
                    .contentShape(Rectangle())
            }
            // Borderless, so a tap on the text is not a tap on the X; grey
            // rather than the accent, as the system's own close glyphs are.
            .buttonStyle(.borderless)
            .tint(.secondary)
            .accessibilityLabel(served(PickerNotice.collapseKey, or: PickerNotice.fallbackCollapse))
            .accessibilityFocused($noticeFocus, equals: .close(notice))
        }
        .padding(.vertical, 4)
    }

    /// `oneLine` holds each label at its natural width, or a label would wrap
    /// inside its capsule rather than let the stack take over.
    @ViewBuilder private func pills(_ folded: [PickerNotice], oneLine: Bool) -> some View {
        ForEach(folded, id: \.self) { notice in
            let label = served(notice.shortKey, or: notice.fallbackShort)
            Button {
                app.unfold(notice)
                focus(.close(notice))
            } label: {
                // Not a `Label`: inside a List that takes the row's style, whose
                // fixed icon column pushes the words off to the right.
                HStack(spacing: 6) {
                    Image(systemName: notice.symbol)
                    Text(label).fixedSize(horizontal: oneLine, vertical: false)
                }
                .font(.footnote)
                .foregroundStyle(.primary)
            }
            .accessibilityLabel(label)
            // A neutral capsule: the pill is a way back to the words, not an
            // action, so it does not take the accent.
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .tint(.gray)
            .accessibilityFocused($noticeFocus, equals: .pill(notice))
        }
    }

    /// The control that should take the focus exists only on the next pass.
    private func focus(_ target: NoticeFocus) {
        Task { @MainActor in
            await Task.yield()
            noticeFocus = target
        }
    }

    /// A notice string from `GET /picker/config`, never through `mobile`: this
    /// is compliance text, and an older server that predates the key gets the
    /// English the contract names.
    private func served(_ key: String, or fallback: String) -> String {
        if let v = picker?.strings[key], !v.isEmpty { return v }
        return fallback
    }

    // P-11 (native words), T-08 and T-09 (the server's words).
    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            Menu {
                Button {
                    showServers = true
                } label: {
                    Label(Native.server, systemImage: "server.rack")
                }
                Button {
                    showLanguages = true
                } label: {
                    Label(strings.mobile("language"), systemImage: "globe")
                }
                // P-15. A menu Picker rather than a sheet of its own: three
                // fixed choices the app owns, unlike the server list and the
                // language list, which are both served and both open-ended.
                Picker(
                    selection: Binding(
                        get: { app.preferences.appearance },
                        set: { app.setAppearance($0) })
                ) {
                    Text(Native.appearanceDark).tag(SplouchCore.Appearance.dark)
                    Text(Native.appearanceLight).tag(SplouchCore.Appearance.light)
                    Text(Native.appearanceAuto).tag(SplouchCore.Appearance.auto)
                } label: {
                    Label(Native.appearance, systemImage: "circle.lefthalf.filled")
                }
                .pickerStyle(.menu)
                // T-09's short/long control, withdrawn: every meet renders the
                // long labels (Preferences.effectiveLabelStyle). Kept rather
                // than deleted so putting it back is uncommenting this and
                // returning `labelStyle` from that property. The strings
                // `prefs_labels`, `prefs_short` and `prefs_long` are still
                // served, so nothing on the server side has to change either.
                //
                // Picker(selection: Binding(get: { app.preferences.labelStyle },
                //                           set: { app.setLabelStyle($0) })) {
                //     Text(strings.mobile("prefs_short")).tag(SplouchCore.LabelStyle.short)
                //     Text(strings.mobile("prefs_long")).tag(SplouchCore.LabelStyle.long)
                // } label: {
                //     Label(strings.mobile("prefs_labels"), systemImage: "textformat.abc")
                // }
                // .pickerStyle(.menu)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }
}

private enum NoticeFocus: Hashable {
    case pill(PickerNotice)
    case close(PickerNotice)
}

extension PickerNotice {
    /// The pill's icon, the same thing on every client. Not a shield or a
    /// raised hand: those read as a privacy control, and there is none.
    fileprivate var symbol: String {
        switch self {
        case .results: "hourglass"  // pending validation, not an error
        case .attendance: "person.2"  // the visitors being counted
        }
    }
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
            self.searchable(text: text, placement: .navigationBarDrawer(displayMode: .always), prompt: Text(prompt))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)  // folded either way
            #else
            self.searchable(text: text, prompt: Text(prompt))
            #endif
        } else {
            self
        }
    }

    @ViewBuilder fileprivate func trimmedTop(_ trim: Bool) -> some View {
        if trim {
            self.contentMargins(.top, 0, for: .scrollContent)
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
/// its own — the list draws all three.
struct MeetCard: View {
    let meet: MeetSummary
    let imageURL: URL?
    let unnamed: String
    /// The server's word for a retained meet with no relay (`mobile.offline`).
    var offline: String = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    /// The one colour here that is the product rather than the chrome, so it is
    /// the only one not taken from the system palette.
    private static let liveGreen = Color(hex: "#4CAF50")

    var body: some View {
        HStack(spacing: 12) {
            // P-02: the live dot leads the row, ahead of the meet's image.
            liveDot
            // The slot is reserved whether or not the meet carries an image, so
            // titles line up down the list; a meet without one shows the same
            // empty tile the image shows while it loads.
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
            VStack(alignment: .leading, spacing: 4) {
                // The name wraps rather than shrinking. On one line with a 0.5
                // floor a long name hit that floor in portrait — half of
                // `.headline`, about 8.5pt — because the row is narrow there.
                Text(meet.name.isEmpty ? unnamed : meet.name)
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
                let details = [meet.meetDate, meet.location, meet.offline ? offline : ""].filter { !$0.isEmpty }
                if !details.isEmpty {
                    Text(details.joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary)
                }
                if !meet.sport.isEmpty {
                    Text(meet.sport).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            // The disclosure glyph at the weight and colour the system draws it,
            // since an async open cannot be a NavigationLink.
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                // Decoration: the row is already a button.
                .accessibilityHidden(true)
        }
        .padding(.vertical, 4)
        .opacity(meet.offline ? 0.75 : 1)
    }

    private var placeholder: some View { Color.secondary.opacity(0.15) }

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
