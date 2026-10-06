import SplouchCore
import SwiftUI

#if os(iOS)
import UIKit
#endif

/// N-02: who this device follows at the meet, how early it is told, and
/// whether the console's heat counts too. Every change is saved and sent at
/// once (N-07) — there is nothing to confirm, so the bar's checkmark only
/// closes, as the filter sheet's does.
///
/// A `Form`, the platform's settings idiom: swimmers are rows that swipe to
/// delete, the two ways of counting ahead are a segmented control, the three
/// values a picker, and the privacy line is the last section's footer, where
/// Settings puts what a switch means.
struct NotificationsSheet: View {
    let ctx: MeetContext
    let privacyURL: URL
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var query = ""
    @FocusState private var searching: Bool

    private var follows: MeetFollows { ctx.follows }
    private var refused: Bool { ctx.push?.permission == .refused }

    var body: some View {
        NavigationStack {
            Form {
                if refused { refusedSection }
                swimmersSection
                leadSection
                selectedSection
            }
            .navigationTitle(Native.notifications)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Label(Native.done, systemImage: "checkmark").labelStyle(.iconOnly)
                    }
                }
            }
            .sensoryFeedback(.impact(weight: .light), trigger: follows.swimmers.count)
            // N-04: the answer can change in Settings while the sheet is away.
            .task { await ctx.push?.refresh() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await refreshAndResend() } }
            }
        }
    }

    // MARK: - Sections

    /// N-04: notifications are off for the app. The follows stay; the way to
    /// turn them on is the system's own page for this app.
    private var refusedSection: some View {
        Section {
            Label(Native.notifyDenied, systemImage: "bell.slash")
                .foregroundStyle(.secondary)
            #if os(iOS)
            Button(Native.notifyOpenSettings) {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
            }
            #endif
        }
    }

    private var swimmersSection: some View {
        Section {
            ForEach(follows.swimmers, id: \.self) { s in
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.name)
                    if !s.club.isEmpty { Text(s.club).font(.footnote).foregroundStyle(.secondary) }
                }
                .accessibilityElement(children: .combine)
            }
            .onDelete { offsets in
                var f = follows
                for i in offsets.sorted(by: >) { f.swimmers.remove(at: i) }
                save(f)
            }
            entryField
            if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                let found = suggestions
                if found.isEmpty {
                    Text(ctx.strings.mobile("no_search_results")).foregroundStyle(.secondary)
                }
                ForEach(Array(found.enumerated()), id: \.offset) { _, s in suggestionRow(s) }
            }
        } header: {
            Text(Native.notifySwimmers)
        } footer: {
            if follows.isEmpty { Text(Native.notifyNone) }
        }
    }

    private var leadSection: some View {
        Section(Native.notifyBefore) {
            Picker(Native.notifyBefore, selection: byHeats) {
                Text(Native.notifyByMinutes).tag(false)
                Text(Native.notifyByHeats).tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Picker(Native.notifyWhen, selection: lead) {
                ForEach(choices, id: \.self) { Text(Native.notifyLead($0)).tag($0) }
            }
        }
    }

    private var selectedSection: some View {
        Section {
            Toggle(Native.notifySelected, isOn: selected)
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                Text(Native.notifySelectedFooter)
                // N-09: what leaves the phone, said where it is decided.
                Text(Native.notifyPrivacy)
                Link(Native.privacyPolicy, destination: privacyURL)
            }
        }
    }

    // MARK: - Adding

    /// S-09's index, swimmers and relay teams only: a club is not a person
    /// whose heat comes up.
    private var suggestions: [Suggestion] {
        ctx.suggestions.search(query, limit: 40).filter { $0.kind == .swimmer }.prefix(20).map { $0 }
    }

    private var entryField: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill").foregroundStyle(.tint).accessibilityHidden(true)
            TextField(Native.notifyAdd, text: $query)
                .focused($searching)
                .autocorrectionDisabled()
                #if os(iOS)
            .textInputAutocapitalization(.never)
            .submitLabel(.done)
                #endif
        }
    }

    private func suggestionRow(_ s: Suggestion) -> some View {
        let swimmer = FollowedSwimmer(name: s.name, club: s.club)
        let added = follows.contains(swimmer)
        return Button {
            var f = follows
            f.add(swimmer)
            save(f)
            query = ""
            searching = false
        } label: {
            HStack {
                VStack(alignment: .leading) {
                    Text(s.name).foregroundStyle(.primary)
                    if !s.club.isEmpty { Text(s.club).font(.footnote).foregroundStyle(.secondary) }
                }
                Spacer()
                if added { Image(systemName: "checkmark").foregroundStyle(.secondary) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(added)
    }

    // MARK: - Bindings

    private var choices: [FollowLead] {
        follows.lead.byHeats
            ? FollowLead.heatChoices.map(FollowLead.heats) : FollowLead.minuteChoices.map(FollowLead.minutes)
    }

    private var byHeats: Binding<Bool> {
        Binding(
            get: { follows.lead.byHeats },
            set: { heats in
                var f = follows
                f.lead = heats ? .heats(1) : .standard
                save(f)
            })
    }

    private var lead: Binding<FollowLead> {
        Binding(
            get: { follows.lead },
            set: {
                var f = follows
                f.lead = $0
                save(f)
            })
    }

    private var selected: Binding<Bool> {
        Binding(
            get: { follows.selected },
            set: {
                var f = follows
                f.selected = $0
                save(f)
            })
    }

    private func save(_ f: MeetFollows) {
        Task { await ctx.setFollows(f) }
    }

    /// Back from Settings with notifications allowed: what waited on the device
    /// goes now.
    private func refreshAndResend() async {
        let before = ctx.push?.permission
        await ctx.push?.refresh()
        if before != .allowed, ctx.push?.permission == .allowed { await ctx.registerFollows() }
    }
}
