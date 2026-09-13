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

/// The app shell (app.md §2): three tabs on a pager, a back affordance, and
/// the lifecycle hooks the sockets and the race clock depend on.
struct MeetShell: View {
    @Bindable var ctx: MeetContext
    let app: AppModel
    let onBack: () -> Void

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
    @State private var network = NetworkWatcher()
    @State private var showFilter = false
    @State private var isLandscape = false

    private var tab: Binding<MeetTab> {
        Binding(get: { MeetTab(rawValue: tabRaw) ?? .scoreboard }, set: { tabRaw = $0.rawValue })
    }
    private var palette: Palette { Palette(ctx.colors) }
    private var faces: Faces { Faces(ctx.fonts) }

    var body: some View {
        VStack(spacing: 0) {
            if showsTopBar { topBar }
            pager
            tabBar
        }
        .background(palette.bg.ignoresSafeArea())
        .environment(\.palette, palette)
        .environment(\.faces, faces)
        .onGeometryChange(for: Bool.self) { $0.size.width > $0.size.height } action: { isLandscape = $0 }
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
        // A-09
        .onChange(of: ctx.gone) { _, gone in
            if gone { onBack() }
        }
    }

    /// Only when there is something to put in it: a meet title, a server name or
    /// version notice, or the Schedule tab's filter button.
    private var showsTopBar: Bool {
        !ctx.title.isEmpty || !app.isDefaultServer || app.contractNotice != nil || tab.wrappedValue == .schedule
    }

    // The meet title, and the server name when it is not the default (P-11 note).
    private var topBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(ctx.title).font(faces.text(15, weight: .semibold)).fitOneLine()
                if !app.isDefaultServer || app.contractNotice != nil {
                    // P-11: the server when it is not the default; P-14: the version notice.
                    Text([app.isDefaultServer ? nil : app.serverName, app.contractNotice].compactMap { $0 }.joined(separator: " \u{00B7} "))
                        .font(.caption2).foregroundStyle(palette.thText).fitOneLine()
                }
            }
            Spacer()
            if tab.wrappedValue == .schedule {
                filterButton
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .foregroundStyle(palette.headerValue)
        .background(palette.headerBg)
    }

    // S-08, S-12
    private var filterButton: some View {
        Button { showFilter = true } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.title3)
                .overlay(alignment: .topTrailing) {
                    if ctx.filter.count > 0 {
                        Text("\(ctx.filter.count)")
                            .font(.caption2.bold())
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(palette.time, in: Capsule())
                            .foregroundStyle(palette.bg)
                            .offset(x: 10, y: -8)
                    }
                }
        }
    }

    // A-03: the platform's pager, full-width and drag-tracking.
    @ViewBuilder private var pager: some View {
        #if os(iOS)
        TabView(selection: tab) {
            ScoreboardTab(ctx: ctx, isLandscape: isLandscape).tag(MeetTab.scoreboard)
            ResultsTab(ctx: ctx, isLandscape: isLandscape).tag(MeetTab.results)
            ScheduleTab(ctx: ctx).tag(MeetTab.schedule)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        #else
        switch tab.wrappedValue {
        case .scoreboard: ScoreboardTab(ctx: ctx, isLandscape: isLandscape)
        case .results: ResultsTab(ctx: ctx, isLandscape: isLandscape)
        case .schedule: ScheduleTab(ctx: ctx)
        }
        #endif
    }

    // A-01, A-07: labels under icons in portrait, icons only in landscape.
    // A-02: the way back to the picker sits at the left, as an arrow only.
    private var tabBar: some View {
        HStack(spacing: 0) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.title3)
                    .frame(width: 56, height: isLandscape ? 28 : 40)
                    .padding(.vertical, isLandscape ? 4 : 6)
                    .foregroundStyle(palette.thText)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(ctx.strings.mobile("back_to_meets"))
            ForEach(MeetTab.allCases, id: \.rawValue) { t in
                Button { tab.wrappedValue = t } label: {
                    VStack(spacing: 2) {
                        Image(systemName: t.symbol).font(.title3)
                        if !isLandscape {
                            Text(ctx.strings.mobile(t.key)).font(.caption2)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, isLandscape ? 4 : 6)
                    .foregroundStyle(tab.wrappedValue == t ? palette.time : palette.thText)
                }
                .buttonStyle(.plain)
            }
        }
        .background(palette.headerBg)
        .overlay(alignment: .top) { palette.headerBorder.frame(height: 1) }
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
