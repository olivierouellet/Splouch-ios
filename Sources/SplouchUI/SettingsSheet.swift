import SplouchCore
import SwiftUI

/// P-19: settings in place of the picker's old `…` menu, which held three
/// choices and could not hold a toggle, its explanation and a link. One `Form`
/// in a sheet, sections in the contract's order (`AppModel.settingsSections`):
/// Display, Privacy, Server, About — what most spectators open settings for
/// first, the server for the few who follow a pool's own. Section names and the toggle are the app's words (T-05); the privacy
/// note and the disclaimer are the server's.
struct SettingsSheet: View {
    let app: AppModel
    @Environment(\.dismiss) private var dismiss
    /// P-20's replay, presented from here so closing it lands back on the row
    /// that opened it (X-10).
    @State private var replayingIntro = false
    @AccessibilityFocusState private var introRowFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                // P-07: no Privacy section while the server is not counting —
                // there is nothing to refuse. The stored choice is kept for its
                // return.
                ForEach(app.settingsSections, id: \.self) { section in
                    switch section {
                    case .display: display
                    case .privacy: privacy
                    case .server: server
                    case .about: about
                    }
                }
            }
            .navigationTitle(Native.settings)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                // A checkmark, as the schedule's filter sheet has: every
                // setting applies as it changes, so this only dismisses.
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Label(Native.done, systemImage: "checkmark").labelStyle(.iconOnly)
                    }
                }
            }
        }
        .introCover(isPresented: $replayingIntro, app: app) { refocus() }
    }

    /// P-11–P-14: one row, the server in use, pushing to the list
    /// (`ServerSheet`). The name over the address, as the list's own rows read;
    /// P-14's notice, when there is one, under it.
    private var server: some View {
        Section {
            NavigationLink {
                ServerSheet(app: app)
            } label: {
                VStack(alignment: .leading) {
                    Text(app.serverName)
                    Text(app.server.display).font(.footnote).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text(Native.server)
        } footer: {
            if let notice = app.contractNotice { Text(notice) }
        }
    }

    /// T-08 and P-15 as `Picker` rows. The language is one row naming the
    /// current choice and pushing the list, since it is served and open-ended —
    /// inline, a server's many languages would push everything else down;
    /// Appearance is three fixed choices the app owns.
    /// Both announce the current choice as selected (X-06) on their own.
    private var display: some View {
        Section(Native.settingsDisplay) {
            Picker(
                Native.language,
                selection: Binding(
                    get: { app.preferences.language },
                    set: { lang in Task { await app.setLanguage(lang) } })
            ) {
                // The device's own language, which is what the picker resolves
                // from when nothing is stored.
                Text(Native.languageAuto).tag(String?.none)
                ForEach(app.locales, id: \.code) { locale in
                    Text(locale.name).tag(Optional(locale.code))
                }
            }
            .pushedChoices()
            Picker(
                Native.appearance,
                selection: Binding(
                    get: { app.preferences.appearance },
                    set: { app.setAppearance($0) })
            ) {
                Text(Native.appearanceDark).tag(SplouchCore.Appearance.dark)
                Text(Native.appearanceLight).tag(SplouchCore.Appearance.light)
                Text(Native.appearanceAuto).tag(SplouchCore.Appearance.auto)
            }
        }
    }

    /// P-07 + C-10: the toggle first, the server's note under it as its
    /// explanation, then the server's policy.
    private var privacy: some View {
        Section {
            CountingToggle(app: app)
        } header: {
            Text(Native.settingsPrivacy)
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                if let note = app.privacyNote { Text(note) }
                Link(Native.privacyPolicy, destination: app.privacyPolicyURL)
            }
        }
    }

    /// P-06's full text, the policy, P-20's replay and the app's version. The
    /// first three need the server's words, so they wait for `GET /picker/config`.
    private var about: some View {
        Section(Native.settingsAbout) {
            if let disclaimer = app.disclaimer {
                Text(disclaimer).font(.subheadline)
            }
            if app.picker != nil {
                Link(Native.privacyPolicy, destination: app.privacyPolicyURL)
            }
            Button(Native.showIntroduction) { replayingIntro = true }
                .disabled(app.picker == nil)
                .accessibilityFocused($introRowFocused)
            LabeledContent(Native.appVersion, value: Self.version)
        }
    }

    /// X-10: the row comes back on the next pass, after the cover is gone.
    private func refocus() {
        Task { @MainActor in
            await Task.yield()
            introRowFocused = true
        }
    }

    /// `2026.10.1 (42)`, as the App Store and TestFlight name a build.
    static var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "—"
        guard let build = info["CFBundleVersion"] as? String, build != short else { return short }
        return "\(short) (\(build))"
    }
}

extension View {
    /// The language list is pushed on iOS; macOS has no such style and builds
    /// for checking only.
    @ViewBuilder fileprivate func pushedChoices() -> some View {
        #if os(iOS)
        self.pickerStyle(.navigationLink)
        #else
        self
        #endif
    }
}

/// C-10's one setting, shared by settings (P-19) and the introduction's last
/// page (P-20) so the two cannot disagree.
struct CountingToggle: View {
    let app: AppModel

    var body: some View {
        Toggle(Native.privacyCount, isOn: Binding(get: { app.counting }, set: { app.setCounting($0) }))
    }
}

/// P-06's tap: the server's full disclaimer. A sheet at half height on a
/// phone, a popover on iPad (`PickerScreen`).
///
/// No `NavigationStack`: the popover is declared inside the picker's list, so
/// it inherits the picker's `.searchable`, and a navigation bar here gave that
/// search field a second home inside the sheet. The title row is drawn instead.
struct DisclaimerSheet: View {
    let title: String
    let text: String

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                    .padding(.horizontal, 56)
                    .accessibilityAddTraits(.isHeader)
                HStack {
                    Spacer()
                    CloseButton(standalone: true)
                }
            }
            .padding(.horizontal)
            .padding(.top, 12)
            ScrollView {
                Text(text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
        // A popover sizes to its content's ideal; a sheet ignores this.
        .frame(minWidth: 320, idealWidth: 400, minHeight: 200, idealHeight: 280)
        .presentationDetents([.medium])
    }
}

/// The platform's own close where it offers one, a Done below that.
/// `standalone` is one outside a toolbar, which draws the role as a word; it
/// gets the toolbar's round glass ✕ by hand.
struct CloseButton: View {
    var standalone = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            if standalone {
                Button(role: .close) {
                    dismiss()
                } label: {
                    Image(systemName: "xmark").frame(width: 32, height: 32)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
            } else {
                Button(role: .close) { dismiss() }
            }
        } else {
            Button(Native.done) { dismiss() }
        }
    }
}
