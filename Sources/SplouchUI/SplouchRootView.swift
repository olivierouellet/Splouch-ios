import SwiftUI
import SplouchCore

/// The app: the meet picker on a cloud, straight to the board on a Pi (P-08,
/// app.md §0.2), and the way back (A-02, A-09).
public struct SplouchRootView: View {
    @State private var app: AppModel
    @State private var meet: MeetContext?
    @State private var opening = false
    @State private var openError = false

    public init(app: AppModel) {
        _app = State(initialValue: app)
    }

    public var body: some View {
        ZStack {
            if let meet {
                MeetShell(ctx: meet, app: app) {
                    Task { await meet.stop() }
                    self.meet = nil
                }
                .transition(.move(edge: .trailing))
            } else {
                PickerScreen(app: app, opening: opening) { summary in
                    await open { try await app.open(summary) }
                } openPi: {
                    await open { try await app.openPi() }
                }
                .transition(.move(edge: .leading))
            }
        }
        .animation(.default, value: meet == nil)
        .task {
            await app.start()
            if app.isPi { await open { try await app.openPi() } }
        }
        .onChange(of: app.isPi) { _, isPi in
            if isPi, meet == nil { Task { await open { try await app.openPi() } } }
        }
        .alert(app.strings.display("connection_lost"), isPresented: $openError) {
            Button(app.strings.mobile("ok"), role: .cancel) {}
        }
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
            await app.load()   // the meet is gone: refresh the list (A-09)
        } catch {
            openError = true
        }
    }
}
