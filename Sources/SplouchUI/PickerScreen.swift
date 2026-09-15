import SwiftUI
import SplouchCore

/// The meet picker (app.md §1). Language is the device's, not a meet's. Its
/// chrome and preference controls are the server's words (`mobile`, T-05);
/// the server menu and the connection error are the app's.
struct PickerScreen: View {
    let app: AppModel
    let opening: Bool
    let open: (MeetSummary) async -> Void
    let openPi: () async -> Void

    @State private var showServers = false

    private var strings: StringTable { app.strings }
    private var picker: PickerConfig? { app.picker }

    /// The web picker's own palette (`cloud/templates/picker.html`): the list
    /// has no meet to theme it, so it looks the same everywhere.
    private enum Ink {
        static let bg = Color(hex: "#0d0d0d")
        static let text = Color(hex: "#e0e0e0")
        static let title = Color(hex: "#888888")
        static let card = Color(hex: "#1a1a1a")
        static let border = Color(hex: "#2e2e2e")
        static let meta = Color(hex: "#666666")
        static let faint = Color(hex: "#444444")
        static let live = Color(hex: "#4CAF50")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                branding
                if !app.isDefaultServer {
                    // A user who switched and forgot must be able to see it (P-11 note).
                    Label(app.serverName, systemImage: "server.rack")
                        .font(.footnote).foregroundStyle(Ink.meta)
                }
                if let notice = app.contractNotice {
                    // P-14: a notice naming both versions, never a gate.
                    Label(notice, systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(Ink.meta)
                }
                if app.unreachable {
                    unreachable
                } else if app.isPi {
                    Button { Task { await openPi() } } label: {
                        Label(Native.openBoard, systemImage: "sportscourt")
                            .padding(.horizontal, 18).padding(.vertical, 10)
                            .background(Ink.card, in: Capsule())
                            .overlay(Capsule().stroke(Ink.border))
                    }
                    .buttonStyle(.plain)
                } else if app.meets.isEmpty, !app.loading {
                    // P-04 on the platform's empty state. The words stay the
                    // server's (T-05); only the presentation is the system's.
                    ContentUnavailableView(picker?.strings["no_meets"] ?? strings.mobile("no_meets"),
                                           systemImage: "calendar.badge.exclamationmark")
                        .padding(.top, 40)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(app.meets) { meet in
                            Button { Task { await open(meet) } } label: {
                                MeetCard(meet: meet, imageURL: meet.hasPickerImage ? app.api.pickerImageURL(meetID: meet.id) : nil,
                                         unnamed: picker?.strings["unnamed_meet"] ?? strings.mobile("unnamed_meet"),
                                         offline: strings.mobile("offline"),
                                         card: Ink.card, border: Ink.border, text: Ink.text, meta: Ink.meta, live: Ink.live)
                            }
                            .buttonStyle(.plain)
                            .disabled(opening)
                        }
                    }
                }
                footer
            }
            .padding()
        }
        .background(Ink.bg.ignoresSafeArea())
        .foregroundStyle(Ink.text)
        .tint(Ink.text)
        .refreshable { await app.load() }   // P-09
        .overlay { if app.loading && app.meets.isEmpty { ProgressView().tint(Ink.meta) } }
        .toolbar { toolbar }
        .sheet(isPresented: $showServers) { ServerSheet(app: app) }
    }

    // P-05
    @ViewBuilder private var branding: some View {
        let title = picker?.title ?? app.serverName
        let logo = (picker?.hasLogo ?? false) ? AsyncImage(url: app.api.pickerLogoURL()) { $0.resizable().scaledToFit() } placeholder: { EmptyView() }
            .frame(maxHeight: 80) : nil
        VStack(spacing: 8) {
            if picker?.logoAbove ?? false { logo }
            Text(title)
                .font(.title2.weight(.regular))
                .textCase(.uppercase)
                .tracking(1.5)
                .foregroundStyle(Ink.title)
                .multilineTextAlignment(.center)
            if !(picker?.logoAbove ?? false) { logo }
        }
        .padding(.top)
    }

    /// A connection error is about the device, so it is native (T-05).
    private var unreachable: some View {
        ContentUnavailableView {
            Label(Native.serverUnreachable, systemImage: "wifi.exclamationmark")
        } actions: {
            Button(Native.retry) { Task { await app.load() } }
        }
        .padding(.top, 40)
    }

    // P-06, P-07: served, never compiled in.
    @ViewBuilder private var footer: some View {
        if let p = picker {
            VStack(spacing: 8) {
                if let d = p.strings["results_disclaimer"], !d.isEmpty {
                    Text(d).font(.footnote).foregroundStyle(Ink.meta).multilineTextAlignment(.center)
                }
                if p.analyticsEnabled, let n = p.strings["privacy_note"], !n.isEmpty {
                    Text(n).font(.footnote).foregroundStyle(Ink.faint).multilineTextAlignment(.center)
                }
            }
            .padding(.top, 24)
        }
    }

    // P-11 (native words), T-08 and T-09 (the server's words).
    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            Menu {
                Button { showServers = true } label: {
                    Label(Native.server, systemImage: "server.rack")
                }
                Picker(selection: Binding(get: { app.preferences.language ?? "" },
                                          set: { v in Task { await app.setLanguage(v.isEmpty ? nil : v) } })) {
                    Text(strings.mobile("language_auto")).tag("")
                    ForEach(app.locales, id: \.code) { Text($0.name).tag($0.code) }
                } label: {
                    Label(strings.mobile("language"), systemImage: "globe")
                }
                .pickerStyle(.menu)
                Picker(selection: Binding(get: { app.preferences.labelStyle },
                                          set: { app.setLabelStyle($0) })) {
                    Text(strings.mobile("prefs_short")).tag(SplouchCore.LabelStyle.short)
                    Text(strings.mobile("prefs_long")).tag(SplouchCore.LabelStyle.long)
                } label: {
                    Label(strings.mobile("prefs_labels"), systemImage: "textformat.abc")
                }
                .pickerStyle(.menu)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }
}

/// P-01, P-02, P-03.
struct MeetCard: View {
    let meet: MeetSummary
    let imageURL: URL?
    let unnamed: String
    /// The server's word for a retained meet with no relay (`mobile.offline`).
    var offline: String = ""
    var card: Color = Color(hex: "#1a1a1a")
    var border: Color = Color(hex: "#2e2e2e")
    var text: Color = Color(hex: "#e0e0e0")
    var meta: Color = Color(hex: "#666666")
    var live: Color = Color(hex: "#4CAF50")
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        HStack(spacing: 12) {
            // P-02: the live dot leads the row, ahead of the meet's image.
            liveDot
            // The slot is reserved whether or not the meet carries an image, so
            // titles line up down the list; a meet without one shows the same
            // empty tile the image shows while it loads.
            Group {
                if let imageURL {
                    AsyncImage(url: imageURL) { $0.resizable().scaledToFill() } placeholder: { border }
                } else {
                    border
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 4) {
                // The name wraps rather than shrinking. On one line with a 0.5
                // floor a long name hit that floor in portrait — half of
                // `.headline`, about 8.5pt — because the card is narrow there.
                // The card grows by a line instead; landscape is wide enough
                // that nothing changes.
                Text(meet.name.isEmpty ? unnamed : meet.name)
                    .font(.headline).foregroundStyle(text)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
                let details = [meet.meetDate, meet.location, meet.offline ? offline : ""].filter { !$0.isEmpty }
                if !details.isEmpty {
                    Text(details.joined(separator: " · ")).font(.subheadline).foregroundStyle(meta)
                }
                if !meet.sport.isEmpty {
                    Text(meet.sport).font(.caption).foregroundStyle(meta)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(meta)
        }
        .padding(14)
        .background(card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(border))
        .opacity(meet.offline ? 0.75 : 1)
    }

    /// A live meet breathes; a retained one is a hollow ring and holds still.
    /// Both are the same 8pt frame and only `opacity`/`scaleEffect` move, so a
    /// pulsing dot never shifts the image or the text beside it.
    @ViewBuilder private var liveDot: some View {
        if meet.offline {
            Circle().strokeBorder(meta, lineWidth: 1).frame(width: 8, height: 8)
        } else {
            Circle()
                .fill(live)
                .frame(width: 8, height: 8)
                .shadow(color: live.opacity(0.7), radius: 3)
                .opacity(pulsing ? 1 : 0.45)
                .scaleEffect(pulsing ? 1 : 0.78)
                // Core Animation drives this, unlike the board's per-frame
                // TimelineView pulse (L-12) — that one has to start and stop
                // with a lane, this one runs for the life of the card.
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.85).repeatForever(autoreverses: true),
                           value: pulsing)
                .onAppear { pulsing = true }
        }
    }
}
