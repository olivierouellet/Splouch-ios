import SwiftUI
import SplouchCore

/// The app: the meet picker on a cloud, straight to the board on a Pi (P-08,
/// app.md §0.2), and the way back (A-02, A-09).
public struct SplouchRootView: View {
    @State private var app: AppModel
    @State private var meet: MeetContext?
    @State private var opening = false
    /// A native message: the meet is gone, or the server could not be reached.
    @State private var openError: String?
    /// Bumped when a meet opens, purely to fire the haptic.
    @State private var openCount = 0
    /// P-16. An alert button always dismisses its alert — that is the platform's,
    /// not a choice available here — so this is driven from `app.invite` rather
    /// than being it. Every change to the invite raises the alert again, which is
    /// what lets a handshake started inside it report back inside it.
    @State private var showingInvite = false

    public init(app: AppModel) {
        _app = State(initialValue: app)
    }

    public var body: some View {
        // A-02: the meet is pushed onto the picker's stack, so the way back is
        // the system's own back button and edge swipe rather than a chevron
        // parked in the tab bar. Both routes pop through `showingMeet`, which
        // is the single place the session is torn down.
        NavigationStack {
            PickerScreen(app: app, opening: opening) { summary in
                await open { try await app.open(summary) }
            } openPi: {
                await open { try await app.openPi() }
            }
            #if os(iOS)
            .toolbarTitleDisplayMode(.inline)
            #endif
            .navigationDestination(isPresented: showingMeet) {
                if let meet { MeetShell(ctx: meet, app: app) }
            }
        }
        // P-15, and the one place the window's scheme is decided — the board
        // reads it back out of the environment for its own palette, so the bars,
        // the rows and the sheets cannot disagree.
        .preferredColorScheme(scheme)
        .sensoryFeedback(.success, trigger: openCount)
        .task {
            await app.start()
            if app.isPi { await open { try await app.openPi() } }
            #if DEBUG
            // `SPLOUCH_MEET=<id>` opens a meet straight away for screenshots.
            if let id = ProcessInfo.processInfo.environment["SPLOUCH_MEET"], let m = app.meets.first(where: { $0.id == id }) {
                await open { try await app.open(m) }
            }
            // P-16. `SPLOUCH_LINK=<url>` hands the model a scanned code at launch.
            // The OS only routes a real one once the host serves an
            // `apple-app-site-association`, and a simulator cannot be given a
            // signed one; this is the same delivery with the OS's own resolution
            // left out — the iOS answer to `adb shell am start -d`.
            if let link = ProcessInfo.processInfo.environment["SPLOUCH_LINK"] { app.openServerLink(link) }
            #endif
        }
        .onChange(of: app.isPi) { _, isPi in
            if isPi, meet == nil { Task { await open { try await app.openPi() } } }
        }
        // No actions: the platform supplies its own OK.
        .alert(openError ?? "", isPresented: Binding(get: { openError != nil }, set: { if !$0 { openError = nil } })) {}
        // P-16. A universal link arrives as a browsing activity, not as a URL:
        // `applinks:splouch.ca` is what the OS matched, and `.onOpenURL` would
        // only ever fire for a custom scheme this app deliberately does not have.
        // It is on the root so a code scanned while a meet is open reaches the
        // model too — the prompt goes over the board, and the meet is left alone
        // until the yes.
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            if let url = activity.webpageURL { app.openServerLink(url.absoluteString) }
        }
        .alert(invitePrompt?.title ?? "", isPresented: $showingInvite) {
            if let prompt = invitePrompt { inviteButtons(prompt) }
        } message: {
            if let message = invitePrompt?.message { Text(message) }
        }
        // A presented alert keeps the words it was presented with: SwiftUI builds
        // its title, message and buttons once and does not rebuild them under the
        // reader. So every change to the invite takes the alert down and puts it
        // back up a turn later — the question, then `Checking…`, then the failure
        // if there is one. It is a blink, and it is the price of the failure being
        // read where the question was asked rather than behind an untouched
        // picker. It comes down for good when the model drops the invite, which is
        // the yes that worked and the reader's no.
        .onChange(of: app.invite) { _, invite in
            showingInvite = false
            if invite != nil { Task { @MainActor in showingInvite = app.invite != nil } }
        }
        .onAppear { showingInvite = app.invite != nil }
    }

    /// P-16: the prompt a scanned code raised, nil when there is none.
    private var invitePrompt: ServerInvitePrompt? {
        app.invite.map(ServerInvitePrompt.init)
    }

    @ViewBuilder private func inviteButtons(_ prompt: ServerInvitePrompt) -> some View {
        Button(prompt.confirmLabel) {
            // Nothing to agree to — a dead link, or the server already in use, which
            // is asked nothing of the network. Both close on the one button.
            if prompt.nothingToDo { app.dismissInvite() } else { accept() }
        }
        if prompt.showsCancel {
            Button(Native.cancel, role: .cancel) { app.dismissInvite() }
        }
    }

    /// The yes, one turn late, and that is the whole trick: pressing a button
    /// dismisses the alert, so starting the handshake here and now would change
    /// the invite *before* the dismissal and the alert would go down with the
    /// request still running behind it. Deferred by a turn, the dismissal lands
    /// first and `checking` puts the same alert straight back up — so `Checking…`,
    /// and then a server that cannot be reached, are read where the question was
    /// asked rather than behind an untouched picker.
    private func accept() {
        Task { @MainActor in app.acceptInvite() }
    }

    /// P-15, everywhere: the picker, the board and the chrome over both. The meet
    /// used to decide inside itself, from `settings.theme_colors` — which meant a
    /// reader who chose Light got it until they opened a meet, which is where
    /// they were going. `auto` is nil: the device answers, and iOS is free to
    /// change that with the time of day.
    private var scheme: ColorScheme? {
        switch app.preferences.appearance {
        case .dark: return .dark
        case .light: return .light
        case .auto: return nil
        }
    }

    private var showingMeet: Binding<Bool> {
        Binding(get: { meet != nil }, set: { if !$0 { close() } })
    }

    /// Popped, by the back button, the edge swipe, or A-09's `dismiss()`.
    private func close() {
        guard let meet else { return }
        if meet.gone { openError = Native.meetGone }   // A-09
        Task { await meet.stop() }
        self.meet = nil
    }

    private func open(_ make: () async throws -> MeetContext) async {
        guard !opening else { return }
        opening = true
        defer { opening = false }
        do {
            let ctx = try await make()
            ctx.start()
            meet = ctx
            openCount += 1
        } catch APIError.notFound {
            openError = Native.meetGone
            await app.load()   // the meet is gone: refresh the list (A-09)
        } catch {
            openError = Native.serverUnreachable
        }
    }
}
