import SwiftUI
import SplouchCore

enum MeetTab: Int, CaseIterable {
    case scoreboard, results, schedule

    var key: String {
        switch self {
        case .scoreboard: "scoreboard"
        case .results: "results"
        case .schedule: "schedule"
        }
    }

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

    // A-04: platform state restoration.
    @SceneStorage("splouch.tab") private var tabRaw = MeetShell.initialTab

    /// Debug builds honour `SPLOUCH_TAB=scoreboard|results|schedule` in the
    /// launch environment, so a tab can be screenshotted without tapping.
    private static var initialTab: Int {
        #if DEBUG
        if let name = ProcessInfo.processInfo.environment["SPLOUCH_TAB"],
           let t = MeetTab.allCases.first(where: { $0.key == name }) { return t.rawValue }
        #endif
        return MeetTab.scoreboard.rawValue
    }
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @State private var network = NetworkWatcher()
    @State private var showFilter = false
    @State private var isLandscape = false

    private var tab: Binding<MeetTab> {
        Binding(get: { MeetTab(rawValue: tabRaw) ?? .scoreboard }, set: { tabRaw = $0.rawValue })
    }
    private var palette: Palette { Palette(ctx.colors) }
    private var faces: Faces { Faces(ctx.fonts) }

    var body: some View {
        tabs
            .background(palette.bg.ignoresSafeArea())
            .environment(\.palette, palette)
            .environment(\.faces, faces)
            // A meet themes itself (app.md §7), so the system chrome over it —
            // sheets, alerts, the menu — follows the board rather than the
            // picker's dark. The picker keeps its own scheme.
            .preferredColorScheme(RGBA(hex: ctx.colors.bg).isDark ? .dark : .light)
            .navigationTitle(ctx.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbar }
            .sensoryFeedback(.selection, trigger: tabRaw)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { isLandscape = $0.width > $0.height }
            .sheet(isPresented: $showFilter) { FilterSheet(ctx: ctx) }
            .onAppear {
                network.start()
                #if DEBUG
                if let env = ProcessInfo.processInfo.environment["SPLOUCH_TAB"],
                   let t = MeetTab.allCases.first(where: { $0.key == env }) { tabRaw = t.rawValue }
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
            .onChange(of: tabRaw) { _, raw in
                if MeetTab(rawValue: raw) == .results { ctx.session.resultsTabShown() }
            }
            // A-09: the meet is gone, so pop the way the back button would.
            .onChange(of: ctx.gone) { _, gone in
                if gone { dismiss() }
            }
    }

    // A-01: three tabs, icon and label, on the platform's own tab bar — which
    // carries A-07 with it (landscape compacts the items without our help) and
    // brings the selection states and VoiceOver tab traits for free.
    //
    // A-03 does not apply here: the web swiped between tabs because its tabs
    // were iframes, and Android swipes because that is the Material idiom. On
    // iOS a tab bar switches on tap — see the parity.md note.
    private var tabs: some View {
        TabView(selection: tab) {
            ScoreboardTab(ctx: ctx, isLandscape: isLandscape)
                .tabItem { label(.scoreboard) }
                .tag(MeetTab.scoreboard)
            ResultsTab(ctx: ctx, isLandscape: isLandscape)
                .tabItem { label(.results) }
                .tag(MeetTab.results)
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

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        // The title alone is `navigationTitle`; with a subtitle it becomes a
        // two-line principal item, which is the only place iOS 17 has for one.
        if let subtitle {
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
