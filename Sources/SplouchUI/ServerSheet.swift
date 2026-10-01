import SplouchCore
import SwiftUI

/// P-11: the servers on offer; P-12: the ones found on the local network, once
/// asked for;
/// P-13: one added by hand, checked with `GET /server` before it is saved.
/// Every word here is about the app or the device, so it is native (T-05).
struct ServerSheet: View {
    let app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var bonjour = BonjourBrowser()
    /// P-12: bumped by each tap on Search; the browse's time limit runs per tap.
    @State private var search = 0
    @State private var typed = ""
    @State private var checking = false
    @State private var checkError: String?
    /// P-13: the row a swipe just took away, while its Undo is on offer.
    @State private var removed: RemovedServer?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(app.knownServers) { s in
                        row(s.name, s.address)
                            .swipeActions(edge: .trailing) {
                                if let saved = app.preferences.savedServers.first(where: { $0.id == s.id }) {
                                    // Only hand-added servers can be removed; the rest are data.
                                    Button(role: .destructive) {
                                        removed = app.removeSavedServer(saved)
                                    } label: {
                                        Label(Native.remove, systemImage: "trash")
                                    }
                                }
                            }
                    }
                }
                // P-12: nothing is browsed until this is tapped. A browse in an
                // idle sheet costs battery, and iOS's local-network prompt should
                // answer something the reader did rather than the sheet opening.
                Section(Native.localServer) {
                    if bonjour.browsing {
                        if bonjour.found.isEmpty {
                            ProgressView().frame(maxWidth: .infinity)
                        }
                        ForEach(bonjour.found) { f in row(f.name, f.address) }
                    } else {
                        if search > 0 {
                            Text(Native.localNoneFound).foregroundStyle(.secondary)
                        }
                        Button(search > 0 ? Native.localSearchAgain : Native.localSearch) {
                            search += 1
                            bonjour.start()
                        }
                    }
                }
                // One row, not three. The section header already says "Add
                // server", so a button repeating it underneath was the same
                // words twice and a row that did nothing until the field was
                // filled. The field submits itself — return key, or the arrow
                // that appears once there is something to send — and the
                // footer carries the progress and the error.
                Section {
                    HStack(spacing: 8) {
                        TextField(Native.serverPlaceholder, text: $typed)
                            .textContentType(.URL)
                            .autocorrectionDisabled()
                            #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .submitLabel(.go)
                            #endif
                            .onSubmit { Task { await add() } }
                        if checking {
                            ProgressView()
                        } else if !typed.trimmingCharacters(in: .whitespaces).isEmpty {
                            Button {
                                Task { await add() }
                            } label: {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.title2)
                                    .symbolRenderingMode(.hierarchical)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Native.addServer)
                        }
                    }
                } header: {
                    Text(Native.addServer)
                } footer: {
                    if checking {
                        Text(Native.checking)
                    } else if let checkError {
                        Text(checkError).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(Native.server)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { cancelButton }
            }
        }
        .overlay(alignment: .bottom) { undoBar }
        .animation(.default, value: removed)
        // One Undo at a time, for a few seconds: long enough to read and reach,
        // short enough that it is not still offering a server removed a while ago.
        // A second removal restarts it for the new row, as a snackbar would.
        .task(id: removed) {
            guard let shown = removed else { return }
            AccessibilityNotification.Announcement(Native.serverRemoved).post()
            try? await Task.sleep(for: .seconds(6))
            if removed == shown { removed = nil }
        }
        // P-12: ~10 s with nothing found ends the browse and says so. Once
        // something answers, it runs on until the sheet closes. A failed browse
        // stops itself, and lands on the same answer.
        .task(id: search) {
            guard search > 0, (try? await Task.sleep(for: .seconds(10))) != nil else { return }
            if bonjour.found.isEmpty { bonjour.stop() }
        }
        .onDisappear { bonjour.stop() }
    }

    /// The platform has no snackbar, so this is one: the message and the one
    /// action that answers it, floating over the foot of the sheet.
    @ViewBuilder private var undoBar: some View {
        if let shown = removed {
            HStack(spacing: 12) {
                Text(Native.serverRemoved)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(Native.undo) {
                    app.restoreSavedServer(shown)
                    removed = nil
                }
                .fontWeight(.semibold)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.regularMaterial, in: Capsule())
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    /// The platform's own Cancel where it offers one, ours below that.
    @ViewBuilder private var cancelButton: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            Button(role: .cancel) { dismiss() }
        } else {
            Button(Native.cancel, role: .cancel) { dismiss() }
        }
    }

    /// `.buttonStyle(.plain)` is load-bearing: inside a Button in a List the
    /// default style makes `.primary` and `.secondary` levels of the accent
    /// rather than absolute colours, so the server name and its URL would both
    /// come out tinted. Only the checkmark should take the accent.
    private func row(_ name: String, _ address: ServerAddress) -> some View {
        Button {
            Task {
                await app.switchServer(address)
                dismiss()
            }
        } label: {
            HStack {
                VStack(alignment: .leading) {
                    Text(name).foregroundStyle(.primary)
                    Text(address.url.absoluteString).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                if address == app.server {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // The checkmark is the only thing saying which server is in use, and a
        // glyph says nothing out loud. The trait does.
        .accessibilityAddTraits(address == app.server ? [.isSelected] : [])
    }

    /// P-13: a typo fails here, not at the first blank board.
    private func add() async {
        checking = true
        checkError = nil
        defer { checking = false }
        do {
            let (address, info) = try await app.probe(typed: typed)
            await app.addServer(address, info: info)
            dismiss()
        } catch APIError.invalidAddress {
            checkError = Native.invalidAddress
        } catch APIError.notASplouchServer, APIError.notFound, APIError.notJSON {
            checkError = Native.notSplouch
        } catch {
            checkError = Native.serverUnreachable
        }
    }
}
