import SplouchCore
import SwiftUI

/// P-20: the introduction. Four short pages — icon, title, a sentence or two —
/// paged, skippable from the first, ending on the picker. Pages 1 and 4 are the
/// server's words (`results_disclaimer`, `privacy_note`); the rest is the app's
/// (T-05). Page 4 only while the server counts.
///
/// Finishing and skipping are the same act: both mark it seen, and neither
/// touches counting — page 4's toggle is `C-10`'s own setting, not a consent.
struct IntroView: View {
    let app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    private struct Page: Identifiable {
        let id: Int
        let symbol: String
        let title: String
        let text: String
        var counting = false
    }

    private var pages: [Page] {
        var out = [
            Page(id: 0, symbol: "hourglass", title: Native.introResultsTitle, text: app.disclaimer ?? ""),
            Page(id: 1, symbol: "rectangle.split.3x1", title: Native.introTabsTitle, text: Native.introTabsBody),
            Page(
                id: 2, symbol: "line.3.horizontal.decrease.circle", title: Native.introFollowTitle,
                text: Native.introFollowBody),
        ]
        if app.analyticsEnabled, let note = app.privacyNote {
            out.append(Page(id: 3, symbol: "person.2", title: Native.introCountingTitle, text: note, counting: true))
        }
        return out
    }

    /// Clamped: the server can stop counting while page 4 is on screen.
    private var isLast: Bool { page >= pages.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                if !isLast {
                    Button(Native.introSkip) { finish() }
                        .frame(minHeight: 44)
                }
            }
            .frame(minHeight: 44)
            .padding(.horizontal)

            TabView(selection: $page) {
                ForEach(pages) { p in
                    pageView(p).tag(p.id)
                }
            }
            .pagedTabs()

            Button {
                if isLast {
                    finish()
                } else {
                    withAnimation { page += 1 }
                }
            } label: {
                Text(isLast ? Native.introStart : Native.introNext).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding()
        }
    }

    private func pageView(_ p: Page) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: p.symbol)
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)  // X-07: the title says it
                Text(p.title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(p.text)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                if p.counting {
                    CountingToggle(app: app)
                        .padding()
                        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))
                    Text(Native.privacyWhere)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
    }

    private func finish() {
        app.finishIntro()
        dismiss()
    }
}

extension View {
    /// P-20 over everything: a full-screen cover on iOS, a sheet where there is
    /// none (macOS builds for checking only).
    func introCover(isPresented: Binding<Bool>, app: AppModel, onDismiss: (() -> Void)? = nil) -> some View {
        #if os(iOS)
        fullScreenCover(isPresented: isPresented, onDismiss: onDismiss) { IntroView(app: app) }
        #else
        sheet(isPresented: isPresented, onDismiss: onDismiss) { IntroView(app: app) }
        #endif
    }

    @ViewBuilder fileprivate func pagedTabs() -> some View {
        #if os(iOS)
        self.tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
        #else
        self
        #endif
    }
}
