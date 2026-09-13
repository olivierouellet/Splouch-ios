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
                Section(Native.addServer) {
                    TextField(Native.serverPlaceholder, text: $typed)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        #endif
                        .onSubmit { Task { await add() } }
                    Button { Task { await add() } } label: {
                        HStack {
                            Text(checking ? Native.checking : Native.addServer)
                            if checking { ProgressView().padding(.leading, 8) }
                        }
                    }
                    .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty || checking)
                    if let checkError {
                        Text(checkError).font(.footnote).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(Native.server)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { cancelButton }
            }
        }
        // The app is dark throughout (SplouchRootView), and the default blue
        // accent on a near-black list is hard to read. The rows take the accent
        // too: inside a Button in a List, `.primary` and `.secondary` are
        // levels of the current foreground style, not absolute colours, so the
        // server name and its URL resolve to the tint as well.
        .tint(.yellow)
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
                if address == app.server { Image(systemName: "checkmark") }
            }
        }
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
