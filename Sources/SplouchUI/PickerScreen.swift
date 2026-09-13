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

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                branding
                if !app.isDefaultServer {
                    // A user who switched and forgot must be able to see it (P-11 note).
                    Label(app.serverName, systemImage: "server.rack")
                        .font(.footnote).foregroundStyle(.secondary)
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
                        .foregroundStyle(.secondary)
                        .padding(.top, 40)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(app.meets) { meet in
                            Button { Task { await open(meet) } } label: {
                                MeetCard(meet: meet, imageURL: meet.hasPickerImage ? app.api.pickerImageURL(meetID: meet.id) : nil,
                                         unnamed: picker?.strings["unnamed_meet"] ?? "")
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
        .refreshable { await app.load() }   // P-09
        .overlay { if app.loading && app.meets.isEmpty { ProgressView() } }
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
            Text(title).font(.largeTitle.bold()).multilineTextAlignment(.center)
            if !(picker?.logoAbove ?? false) { logo }
        }
        .padding(.top)
    }

    private var unreachable: some View {
        VStack(spacing: 12) {
            Text(strings.display("connection_lost")).foregroundStyle(.secondary)
            Button { Task { await app.load() } } label: { Text(strings.mobile("retry")) }
                .buttonStyle(.bordered)
        }
        .padding(.top, 40)
    }

    // P-06, P-07
    @ViewBuilder private var footer: some View {
        if let p = picker {
            VStack(spacing: 8) {
                if let d = p.strings["results_disclaimer"], !d.isEmpty {
                    Text(d).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                if p.analyticsEnabled, let n = p.strings["privacy_note"], !n.isEmpty {
                    Text(n).font(.footnote).foregroundStyle(.tertiary).multilineTextAlignment(.center)
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

    var body: some View {
        HStack(spacing: 12) {
            if let imageURL {
                AsyncImage(url: imageURL) { $0.resizable().scaledToFill() } placeholder: { Color.secondary.opacity(0.15) }
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle().fill(meet.offline ? Color.secondary.opacity(0.4) : Color.green).frame(width: 8, height: 8)
                    Text(meet.name.isEmpty ? unnamed : meet.name).font(.headline).fitOneLine()
                }
                Text([meet.meetDate, meet.location].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.subheadline).foregroundStyle(.secondary)
                if !meet.sport.isEmpty {
                    Text(meet.sport).font(.caption).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .opacity(meet.offline ? 0.7 : 1)
    }
}
