import SwiftUI
import SplouchCore

/// The meet picker (app.md §1). Language is the device's, not a meet's.
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
                        Label(app.serverName, systemImage: "sportscourt")
                    }
                    .buttonStyle(.borderedProminent)
                } else if app.meets.isEmpty, !app.loading {
                    Text(picker?.strings["no_meets"] ?? strings.mobile("no_meets"))
                        .foregroundStyle(Ink.faint)
                        .padding(.top, 40)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(app.meets) { meet in
                            Button { Task { await open(meet) } } label: {
                                MeetCard(meet: meet, imageURL: meet.hasPickerImage ? app.api.pickerImageURL(meetID: meet.id) : nil,
                                         unnamed: picker?.strings["unnamed_meet"] ?? "",
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

    private var unreachable: some View {
        VStack(spacing: 16) {
            Text(strings.display("connection_lost")).foregroundStyle(Ink.faint)
            Button { Task { await app.load() } } label: {
                Text(strings.mobile("retry"))
                    .padding(.horizontal, 18).padding(.vertical, 8)
                    .background(Ink.card, in: Capsule())
                    .overlay(Capsule().stroke(Ink.border))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 40)
    }

    // P-06, P-07
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

    // P-11, T-08, T-09
    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            Menu {
                Button { showServers = true } label: {
                    Label(strings.mobile("server"), systemImage: "server.rack")
                }
                Picker(selection: Binding(get: { app.preferences.language ?? "" },
                                          set: { v in Task { await app.setLanguage(v.isEmpty ? nil : v) } })) {
                    Text(strings.mobile("prefs_auto")).tag("")
                    ForEach(app.locales, id: \.code) { Text($0.name).tag($0.code) }
                } label: {
                    Label(strings.mobile("language"), systemImage: "globe")
                }
                .pickerStyle(.menu)
                Picker(selection: Binding(get: { app.preferences.labelStyle?.rawValue ?? "" },
                                          set: { app.setLabelStyle(SplouchCore.LabelStyle(rawValue: $0)) })) {
                    Text(strings.mobile("prefs_auto")).tag("")
                    Text(sample(.short)).tag(SplouchCore.LabelStyle.short.rawValue)
                    Text(sample(.long)).tag(SplouchCore.LabelStyle.long.rawValue)
                } label: {
                    Label(strings.mobile("prefs_labels"), systemImage: "textformat.abc")
                }
                .pickerStyle(.menu)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    /// The style shown by its own words, so nothing is translated here (T-04).
    private func sample(_ style: SplouchCore.LabelStyle) -> String {
        let t = strings.labels(style)
        return [t["event"], t["heat"]].compactMap { $0 }.joined(separator: " · ")
    }
}

/// P-01, P-02, P-03.
struct MeetCard: View {
    let meet: MeetSummary
    let imageURL: URL?
    let unnamed: String
    var card: Color = Color(hex: "#1a1a1a")
    var border: Color = Color(hex: "#2e2e2e")
    var text: Color = Color(hex: "#e0e0e0")
    var meta: Color = Color(hex: "#666666")
    var live: Color = Color(hex: "#4CAF50")

    var body: some View {
        HStack(spacing: 12) {
            if let imageURL {
                AsyncImage(url: imageURL) { $0.resizable().scaledToFill() } placeholder: { border }
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(meet.offline ? Color.clear : live)
                        .overlay(Circle().stroke(meet.offline ? meta : Color.clear))
                        .shadow(color: meet.offline ? .clear : live.opacity(0.7), radius: 3)
                        .frame(width: 8, height: 8)
                    Text(meet.name.isEmpty ? unnamed : meet.name).font(.headline).foregroundStyle(text).fitOneLine()
                }
                Text([meet.meetDate, meet.location].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.subheadline).foregroundStyle(meta)
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
}
