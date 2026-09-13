import SwiftUI
import SplouchCore

/// P-11: the servers on offer; P-12: the ones found on the local network;
/// P-13: one added by hand, checked with `GET /server` before it is saved.
struct ServerSheet: View {
    let app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var bonjour = BonjourBrowser()
    @State private var typed = ""
    @State private var checking = false
    @State private var checkError = false

    private var strings: StringTable { app.strings }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(app.knownServers) { s in
                        row(s.name, s.address, kind: s.address == app.defaultServer ? "cloud" : nil)
                    }
                    .onDelete { offsets in
                        // Only hand-added servers can be removed; the rest are data.
                        let known = app.knownServers
                        for i in offsets {
                            if let saved = app.preferences.savedServers.first(where: { $0.id == known[i].id }) {
                                app.removeSavedServer(saved)
                            }
                        }
                    }
                }
                if bonjour.browsing {
                    Section(strings.mobile("nearby")) {
                        if bonjour.found.isEmpty {
                            HStack { ProgressView(); Text(strings.display("waiting_server")).foregroundStyle(.secondary) }
                        }
                        ForEach(bonjour.found) { f in row(f.name, f.address, kind: "pi") }
                    }
                }
                Section(strings.mobile("add_server")) {
                    TextField(strings.mobile("server_placeholder"), text: $typed)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        #endif
                        .onSubmit { Task { await add() } }
                    Button { Task { await add() } } label: {
                        HStack {
                            Text(strings.mobile("add_server"))
                            if checking { ProgressView().padding(.leading, 8) }
                        }
                    }
                    .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty || checking)
                    if checkError {
                        Text(strings.display("connection_lost")).font(.footnote).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(strings.mobile("server"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(strings.mobile("cancel")) { dismiss() }
                }
            }
        }
        .onAppear { bonjour.start() }
        .onDisappear { bonjour.stop() }
    }

    private func row(_ name: String, _ address: ServerAddress, kind: String?) -> some View {
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
        checkError = false
        defer { checking = false }
        do {
            let (address, info) = try await app.probe(typed: typed)
            await app.addServer(address, info: info)
            dismiss()
        } catch {
            checkError = true
        }
    }
}
