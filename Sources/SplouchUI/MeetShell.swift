import SwiftUI
import SplouchCore

/// A-04 stores a choice, not a number: the raw value is the tab's own name, so
/// a stored selection survives the tab *set* changing under it (A-11) instead
/// of meaning a different tab once one is removed.
enum MeetTab: String, CaseIterable {
    case scoreboard, results, schedule

    var key: String { rawValue }

    var symbol: String {
        switch self {
        case .scoreboard: "timer"
        case .results: "list.number"
        case .schedule: "calendar"
        }
    }
}

/// The app shell (app.md §2): three tabs on the platform's tab bar, inside the
/// picker's navigation stack, and the lifecycle hooks the sockets and the race
/// clock depend on.
///
/// A-02's way back is the stack's own back button, so this view takes no
/// callback: `dismiss()` pops it and `SplouchRootView` tears the session down
/// from the one place that owns it.
struct MeetShell: View {
    @Bindable var ctx: MeetContext
    let app: AppModel

    // A-04: platform state restoration, keyed by the tab's name.
    @SceneStorage("splouch.tab") private var tabKey = MeetShell.initialTab

    /// Debug builds honour `SPLOUCH_TAB=scoreboard|results|schedule` in the
    /// launch environment, so a tab can be screenshotted without tapping.
    private static var initialTab: String {
        #if DEBUG
        if let name = ProcessInfo.processInfo.environment["SPLOUCH_TAB"],
           let t = MeetTab(rawValue: name) { return t.key }
        #endif
        return MeetTab.scoreboard.key
    }
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @State private var network = NetworkWatcher()
    @State private var showFilter = false
    @State private var isLandscape = false
    /// Width of the shell, so the landscape header can be given a real width to
    /// align inside (see `toolbar`).
    @State private var width: CGFloat = 0
    /// Portrait: the lanes have asked for the header row. The tab decides it —
    /// it is the only view that can measure both a lane and the header band —
    /// and it arrives here as a preference.
    @State private var boardNeedsBar = false

    /// A-11: the Results tab exists only for a meet whose console times.
    /// Nothing else is conditional — the Scoreboard is exactly as useful (it is
    /// what the operator is driving by hand) and the Schedule is the whole
    /// start list either way.
    private var visibleTabs: [MeetTab] {
        ctx.showsResults ? MeetTab.allCases : MeetTab.allCases.filter { $0 != .results }
    }

    /// The stored choice, or the Scoreboard when it names a tab this meet does
    /// not have. The fallback is what catches a spectator standing on Results
    /// when the console is unplugged; a spectator on Schedule is untouched,
    /// because the choice was stored by name and the Schedule is still there.
    private var selection: MeetTab {
        let stored = MeetTab(rawValue: tabKey) ?? .scoreboard
        return visibleTabs.contains(stored) ? stored : .scoreboard
    }

    private var tab: Binding<MeetTab> {
        Binding(get: { selection }, set: { tabKey = $0.key })
    }
    @Environment(\.colorScheme) private var colorScheme
    /// P-15: the reader's choice, not the meet's. `colorScheme` is whatever
    /// `SplouchRootView` resolved the preference to — including `auto`, where the
    /// device answers and iOS is free to change it at dusk.
    private var palette: Palette { Palette(colorScheme == .dark ? .dark : .light) }
    private var faces: Faces { Faces(ctx.fonts) }

    var body: some View {
        tabs
            .background(palette.bg.ignoresSafeArea())
            .environment(\.palette, palette)
            .environment(\.faces, faces)
            .navigationTitle(ctx.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbar }
            .sensoryFeedback(.selection, trigger: tabKey)
            .onGeometryChange(for: CGSize.self) { $0.size } action: {
                isLandscape = $0.width > $0.height
                width = $0.width
            }
            .onPreferenceChange(BoardNeedsBarKey.self) { boardNeedsBar = $0 }
            .sheet(isPresented: $showFilter) { FilterSheet(ctx: ctx) }
            .onAppear {
                network.start()
                #if DEBUG
                if let env = ProcessInfo.processInfo.environment["SPLOUCH_TAB"],
                   let t = MeetTab(rawValue: env) { tabKey = t.key }
                #endif
            }
            .onDisappear { network.stop() }
            // C-05: foreground → probe; background → the ticker stops (L-12).
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active: ctx.foregrounded()   // C-05 probe, A-09 check
                default: ctx.session.suspend()
                }
            }
            .onChange(of: network.isOnline) { _, online in
                if online { ctx.session.wake() }
            }
            // R-10: returning to the tab re-joins.
            .onChange(of: tabKey) { _, key in
                if MeetTab(rawValue: key) == .results { ctx.session.resultsTabShown() }
            }
            // A-11: the console changed under us — the config fetch that found
            // out is one this shell already makes (reconnect, foreground,
            // pull-to-refresh, `reload`), so the tab bar follows live. Write the
            // move back rather than deriving it alone: a spectator moved off
            // Results should stay where they were put if a console is plugged
            // in later, not be yanked back mid-tap.
            .onChange(of: ctx.showsResults) { _, _ in
                if MeetTab(rawValue: tabKey) != selection { tabKey = selection.key }
            }
            // A-09: the meet is gone, so pop the way the back button would.
            .onChange(of: ctx.gone) { _, gone in
                if gone { dismiss() }
            }
    }

    // A-01: three tabs, icon and label, on the platform's own tab bar — which
    // carries A-07 with it (landscape compacts the items without our help) and
    // brings the selection states and VoiceOver tab traits for free. A-11 makes
    // it two when the meet has no timing console: the item is not built at all,
    // so the bar genuinely has two, rather than three with one disabled or
    // hidden-but-still-selectable.
    //
    // A-03 does not apply here: the web swiped between tabs because its tabs
    // were iframes, and Android swipes because that is the Material idiom. On
    // iOS a tab bar switches on tap — see the parity.md note.
    private var tabs: some View {
        TabView(selection: tab) {
            ScoreboardTab(ctx: ctx, isLandscape: isLandscape, headerInBar: showsBoardInBar)
                .tabItem { label(.scoreboard) }
                .tag(MeetTab.scoreboard)
            if ctx.showsResults {
                ResultsTab(ctx: ctx, isLandscape: isLandscape, headerInBar: showsBoardInBar)
                    .tabItem { label(.results) }
                    .tag(MeetTab.results)
            }
            ScheduleTab(ctx: ctx)
                .tabItem { label(.schedule) }
                .tag(MeetTab.schedule)
        }
        // T-01 reaches the bar as far as SwiftUI allows: the meet's timing
        // colour marks the selection and its header colour backs the bar. The
        // unselected item has no SwiftUI hook, so it stays the system grey
        // rather than being forced through `UITabBar.appearance()`.
        .tint(palette.time)
        .themedTabBar(palette.headerBg)
    }

    private func label(_ t: MeetTab) -> some View {
        Label(ctx.strings.mobile(t.key), systemImage: t.symbol)
    }

    /// P-11: the server when it is not the default; P-14: the version notice.
    /// Both have to stay visible — a user who switched and forgot cannot answer
    /// "where did my meet go?" from a screen that looks identical either way.
    private var subtitle: String? {
        let parts = [app.isDefaultServer ? nil : app.serverName, app.contractNotice].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
    }

    /// Landscape is short of height and the navigation bar was mostly empty —
    /// a back button in the corner and nothing beside it, with the board's own
    /// EVENT / HEAT / clock row stacked underneath. On a board tab the bar
    /// takes that row instead, which buys back its whole height.
    ///
    /// Portrait does it too, but only on need (below): there the bar is already
    /// carrying the meet's title, so the trade is a real one and not worth
    /// making for a board that fits without it.
    private var showsBoardInBar: Bool {
        tab.wrappedValue != .schedule && (isLandscape || boardNeedsBar)
    }


    /// Short labels, because this is a bar: "EV 12  HT 3", not "EVENT 12
    /// HEAT 3". The words buy nothing the numbers do not already say and the
    /// width they cost is the event name's, which is the one thing here that
    /// can run long.
    @ViewBuilder private var barBoardHeader: some View {
        if tab.wrappedValue == .results {
            let snapshot = ctx.session.results
            BoardHeader(event: snapshot?.event ?? "", heat: snapshot?.heat ?? "",
                        eventName: snapshot.map { ctx.eventName($0.eventName, parts: $0.eventNameParts) } ?? "",
                        labels: ctx.shortLabels, compact: true, showsClock: false)
        } else {
            let board = ctx.session.scoreboard
            BoardHeader(event: board.currentEvent, heat: board.currentHeat,
                        eventName: ctx.eventName(board.eventName, parts: board.eventNameParts),
                        labels: ctx.shortLabels, compact: true, showsClock: false)
        }
    }

    /// The clock is chrome, not a control, so it does not take the glass
    /// capsule iOS 26 gives a toolbar item by default — a pill around a ticking
    /// time reads as something to tap.
    @ToolbarContentBuilder private var clockItem: some ToolbarContent {
        if #available(iOS 26.0, macOS 26.0, *) {
            ToolbarItem(placement: .primaryAction) { WallClock(size: 15) }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .primaryAction) { WallClock(size: 15) }
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        if showsBoardInBar {
            // The principal slot, given an explicit width. It is the one
            // placement iOS 26 draws without wrapping in a glass capsule, but
            // it sizes to its content and centres, so `maxWidth: .infinity`
            // had nothing to expand into and leading alignment did nothing.
            // Handing it the bar's width less the back button and the clock
            // gives it the slack to push EVENT and HEAT to the left edge.
            // `.navigation` was the obvious alternative and is worse: it takes
            // a capsule of its own and lets the meet title back in beside it.
            ToolbarItem(placement: .principal) {
                // Less to reserve in portrait: the bar there holds a back
                // button and the clock, not a back button, the clock and the
                // slack a landscape bar has.
                barBoardHeader.frame(width: max(0, width - (isLandscape ? 200 : 100)), alignment: .leading)
            }
            // Landscape keeps the clock; portrait does not. The row is only up
            // here in portrait because the board ran out of height, and the bar
            // it moved into is 402pt wide, not 874 — the wall clock is the one
            // thing on it that is not about this heat, and the event name is the
            // one thing that runs long. The status bar is still showing the
            // time two points above it.
            if isLandscape { clockItem }
        } else if let subtitle {
            // The title alone is `navigationTitle`; with a subtitle it becomes a
            // two-line principal item, which is the only place iOS 17 has for one.
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(ctx.title).font(.headline).fitOneLine()
                    Text(subtitle).font(.caption2).foregroundStyle(.secondary).fitOneLine()
                }
            }
        }
        if tab.wrappedValue == .schedule {
            ToolbarItem(placement: .primaryAction) { filterButton }
        }
    }

    // S-08, S-12. The count sits beside the symbol rather than in a bubble
    // pinned outside it: a toolbar item is drawn inside a glass capsule that
    // clips, so the offset overlay lost its top-right corner. Filters active
    // also fills the symbol and takes the meet's timing colour, so the state
    // reads at a glance and not only by the digit.
    private var filterButton: some View {
        let count = ctx.filter.count
        return Button { showFilter = true } label: {
            HStack(spacing: 4) {
                Image(systemName: count > 0 ? "line.3.horizontal.decrease.circle.fill"
                                            : "line.3.horizontal.decrease.circle")
                if count > 0 {
                    Text("\(count)").font(.footnote.weight(.semibold)).monospacedDigit()
                }
            }
            .foregroundStyle(count > 0 ? palette.time : Color.primary)
        }
        .accessibilityLabel(ctx.strings.mobile("filter"))
        .accessibilityValue(count > 0 ? "\(count)" : "")
    }
}

private extension View {
    /// `ToolbarPlacement.tabBar` is iOS-only; on macOS the shell is checked for
    /// compilation, not looked at.
    @ViewBuilder func themedTabBar(_ color: Color) -> some View {
        #if os(iOS)
        self.toolbarBackground(color, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
        #else
        self
        #endif
    }
}

// Theme through the environment so every row reads one palette.
private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette(ThemeColors())
}

private struct FacesKey: EnvironmentKey {
    static let defaultValue = Faces(ThemeFonts())
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
    var faces: Faces {
        get { self[FacesKey.self] }
        set { self[FacesKey.self] = newValue }
    }
}
