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
        .preferredColorScheme(.dark)   // the picker is the web picker's dark; a meet themes itself
        .task {
            await app.start()
            if app.isPi { await open { try await app.openPi() } }
            #if DEBUG
            // `SPLOUCH_MEET=<id>` opens a meet straight away for screenshots.
            if let id = ProcessInfo.processInfo.environment["SPLOUCH_MEET"], let m = app.meets.first(where: { $0.id == id }) {
                await open { try await app.open(m) }
            }
            #endif
        }
        .onChange(of: app.isPi) { _, isPi in
            if isPi, meet == nil { Task { await open { try await app.openPi() } } }
        }
        // No actions: the platform supplies its own OK.
        .alert(openError ?? "", isPresented: Binding(get: { openError != nil }, set: { if !$0 { openError = nil } })) {}
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
        } catch APIError.notFound {
            openError = Native.meetGone
            await app.load()   // the meet is gone: refresh the list (A-09)
        } catch {
            openError = Native.serverUnreachable
        }
    }
}
