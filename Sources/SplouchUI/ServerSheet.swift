import SwiftUI
import SplouchCore

/// P-11: the servers on offer; P-12: the ones found on the local network;
/// P-13: one added by hand, checked with `GET /server` before it is saved.
/// Every word here is about the app or the device, so it is native (T-05).
struct ServerSheet: View {
    let app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var bonjour = BonjourBrowser()
    @State private var typed = ""
    @State private var checking = false
    @State private var checkError: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(app.knownServers) { s in
                        row(s.name, s.address)
                            .swipeActions(edge: .trailing) {
                                if let saved = app.preferences.savedServers.first(where: { $0.id == s.id }) {
                                    // Only hand-added servers can be removed; the rest are data.
                                    Button(role: .destructive) { app.removeSavedServer(saved) } label: {
                                        Label(Native.remove, systemImage: "trash")
                                    }
                                }
                            }
                    }
                }
                if bonjour.browsing {
                    Section(Native.nearby) {
                        if bonjour.found.isEmpty {
                            ProgressView()
                        }
                        ForEach(bonjour.found) { f in row(f.name, f.address) }
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
                            Button { Task { await add() } } label: {
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
        .onAppear { bonjour.start() }
        .onDisappear { bonjour.stop() }
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
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
