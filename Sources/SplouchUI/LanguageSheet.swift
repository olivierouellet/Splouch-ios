import SwiftUI
import SplouchCore

/// T-08: the language, per device, applying to every meet opened afterwards.
///
/// It is a sheet rather than a picker nested inside the picker's menu: a menu
/// that opens a menu hides the choice one level down and gives the current
/// value nowhere to show. This is the same shape as the server list — rows,
/// the current one checked — because it is the same kind of choice.
struct LanguageSheet: View {
    let app: AppModel
    @Environment(\.dismiss) private var dismiss

    private var strings: StringTable { app.strings }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    // The device's own language, which is what the picker
                    // resolves from when nothing is stored.
                    row(strings.mobile("language_auto"), code: nil)
                }
                Section {
                    ForEach(app.locales, id: \.code) { locale in
                        row(locale.name, code: locale.code)
                    }
                }
            }
            .navigationTitle(strings.mobile("language"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { cancelButton }
            }
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

    /// `.buttonStyle(.plain)` for the same reason ServerSheet's rows use it:
    /// inside a Button in a List the default style makes `.primary` a level of
    /// the accent, so the name itself would come out tinted.
    private func row(_ name: String, code: String?) -> some View {
        Button {
            Task { await app.setLanguage(code) }
            dismiss()
        } label: {
            HStack {
                Text(name).foregroundStyle(.primary)
                Spacer()
                if app.preferences.language == code {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // As in ServerSheet: the checkmark carries the state and a glyph is
        // silent, so the trait says it instead.
        .accessibilityAddTraits(app.preferences.language == code ? [.isSelected] : [])
    }
}
