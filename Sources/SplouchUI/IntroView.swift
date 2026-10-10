import SplouchCore
import SwiftUI

/// P-20: the introduction. Up to six short pages — icon, title, a sentence per
/// line — paged, skippable from the first, ending on the picker. The first and
/// last are the server's words (`results_disclaimer`, `privacy_note`); the rest
/// is the app's (T-05). The last only while the server counts.
///
/// Finishing and skipping are the same act: both mark it seen, and neither
/// touches counting — the last page's toggle is `C-10`'s own setting, not a consent.
struct IntroView: View {
    let app: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var page = 0

    private struct Page: Identifiable {
        let id: Int
        let symbol: String
        let title: String
        let text: String
        var counting = false
        var laneKey = false
    }

    private var pages: [Page] {
        var out = [
            Page(id: 0, symbol: "hourglass", title: Native.introResultsTitle, text: app.disclaimer ?? ""),
            Page(id: 1, symbol: "magnifyingglass", title: Native.introMeetsTitle, text: Native.introMeetsBody),
            Page(
                id: 2, symbol: "rectangle.split.3x1", title: Native.introTabsTitle, text: Native.introTabsBody,
                laneKey: true),
            Page(id: 3, symbol: "plusminus.circle", title: Native.introTimesTitle, text: Native.introTimesBody),
            Page(
                id: 4, symbol: "line.3.horizontal.decrease.circle", title: Native.introFollowTitle,
                text: Native.introFollowBody),
        ]
        if app.analyticsEnabled, let note = app.privacyNote {
            out.append(Page(id: 5, symbol: "person.2", title: Native.introCountingTitle, text: note, counting: true))
        }
        return out
    }

    /// Clamped: the server can stop counting while the last page is on screen.
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
                Self.withIcons(p.text)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Self.spoken(p.text))
                if p.laneKey {
                    // How to read a lane, in the server's default palette for the
                    // reader's Appearance (P-15) — the board's own, there being no meet yet.
                    LaneKey(
                        words: LaneKeyWords(
                            lane: Native.introKeyLane, club: Native.introKeyClub, time: Native.introKeyTime,
                            gap: Native.introKeyGap, laps: Native.introKeyLaps, place: Native.introKeyPlace)
                    )
                    .environment(\.palette, Palette(colorScheme == .dark ? .dark : .light))
                    .environment(\.faces, Faces(ThemeFonts()))
                }
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

    /// The controls a page names, drawn as they look on screen: `{filter}` in the
    /// text becomes the filter's own symbol, and so on. A name not listed stays as
    /// written, so a server's text with braces in it is left alone.
    nonisolated static let icons = [
        "filter": "line.3.horizontal.decrease.circle",
        "gear": "gearshape",
        "bell": "bell",
        "plusminus": "plusminus.circle",
    ]

    /// Verbatim pieces, so a stray `%` in the text is never a format.
    static func withIcons(_ text: String) -> Text {
        var out = Text(verbatim: "")
        var rest = Substring(text)
        while let open = rest.firstIndex(of: "{"), let close = rest[open...].firstIndex(of: "}") {
            let name = String(rest[rest.index(after: open)..<close])
            let piece =
                icons[name].map { Text(Image(systemName: $0)).foregroundStyle(.tint) }
                ?? Text(verbatim: String(rest[open...close]))
            out = Text("\(out)\(Text(verbatim: String(rest[..<open])))\(piece)")
            rest = rest[rest.index(after: close)...]
        }
        return Text("\(out)\(Text(verbatim: String(rest)))")
    }

    /// What VoiceOver reads: the words alone, since each names its control already —
    /// except `±`, which stands for itself.
    nonisolated static func spoken(_ text: String) -> String {
        var out = text.replacingOccurrences(of: "{plusminus}", with: "±")
        for name in icons.keys {
            out = out.replacingOccurrences(of: " {\(name)}", with: "")
        }
        return out
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
