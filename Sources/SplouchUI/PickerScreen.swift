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
    @State private var showLanguages = false

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
                branding
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            // P-11: a user who switched and forgot must be able to see it.
            // P-14: a notice naming both versions, never a gate.
            if !app.isDefaultServer || app.contractNotice != nil {
                Section {
                    if !app.isDefaultServer {
                        Label(app.serverName, systemImage: "server.rack")
                    }
                    if let notice = app.contractNotice {
                        Label(notice, systemImage: "exclamationmark.triangle")
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            meets
            footer
        }
        .groupedList()
        .refreshable { await app.load() }   // P-09
        .overlay { if app.loading && app.meets.isEmpty { ProgressView() } }
        .toolbar { toolbar }
        .sheet(isPresented: $showServers) { ServerSheet(app: app) }
        .sheet(isPresented: $showLanguages) { LanguageSheet(app: app) }
        // The picker has no meet to theme it, so it keeps the web picker's dark
        // whatever the device is set to. A meet's own screens follow the board
        // instead — see MeetShell. The greys are the system's grouped-background
        // ones rather than the stylesheet's hex, so they track Increase Contrast
        // and match every other app on the device.
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private var meets: some View {
        if app.unreachable {
            Section {
                // A connection error is about the device, so it is native (T-05).
                Unavailable(text: Native.serverUnreachable, symbol: "wifi.exclamationmark",
                            actionLabel: Native.retry) { Task { await app.load() } }
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } else if app.isPi {
            Section {
                Button { Task { await openPi() } } label: {
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
                Unavailable(text: picker?.strings["no_meets"] ?? strings.mobile("no_meets"),
                            symbol: "calendar.badge.exclamationmark")
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } else {
            Section {
                ForEach(app.meets) { meet in
                    Button { Task { await open(meet) } } label: {
                        MeetCard(meet: meet,
                                 imageURL: meet.hasPickerImage ? app.api.pickerImageURL(meetID: meet.id) : nil,
                                 unnamed: picker?.strings["unnamed_meet"] ?? strings.mobile("unnamed_meet"),
                                 offline: strings.mobile("offline"))
                    }
                    .buttonStyle(CardButtonStyle())
                    .disabled(opening)
                }
            }
        }
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
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if !(picker?.logoAbove ?? false) { logo }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // P-06, P-07: served, never compiled in.
    //
    // The two are not the same kind of text and were being drawn as though
    // they were — both footnote-sized, both greyed, both trailing off the
    // bottom of the list. P-06 is the only thing standing between a live feed
    // and a spectator taking it for a result, so it gets a block of its own at
    // full contrast. P-07 really is fine print, and stays fine print, just
    // large enough to read.
    @ViewBuilder private var footer: some View {
        if let p = picker {
            if let d = p.strings["results_disclaimer"], !d.isEmpty {
                Section {
                    Text(d)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
            }
            if p.analyticsEnabled, let n = p.strings["privacy_note"], !n.isEmpty {
                Section {
                    Text(n)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
    }

    // P-11 (native words), T-08 and T-09 (the server's words).
    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            Menu {
                Button { showServers = true } label: {
                    Label(Native.server, systemImage: "server.rack")
                }
                Button { showLanguages = true } label: {
                    Label(strings.mobile("language"), systemImage: "globe")
                }
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

private extension View {
    /// `.insetGrouped` is iOS-only; on macOS the picker is checked for
    /// compilation, not looked at.
    @ViewBuilder func groupedList() -> some View {
        #if os(iOS)
        self.listStyle(.insetGrouped)
        #else
        self.listStyle(.sidebar)
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
                    AsyncImage(url: imageURL) { $0.resizable().scaledToFill() } placeholder: { placeholder }
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
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.85).repeatForever(autoreverses: true),
                           value: pulsing)
                .onAppear { pulsing = true }
        }
    }
}
