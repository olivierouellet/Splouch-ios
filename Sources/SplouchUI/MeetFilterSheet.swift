import SplouchCore
import SwiftUI

/// P-21: the picker's filter. Three sections of checkable rows — club,
/// country, state/province — offering what the list holds. Every tap writes
/// straight to the stored filter, so the list behind is already filtered and
/// the checkmark only confirms, as the schedule's filter sheet does.
struct MeetFilterSheet: View {
    let app: AppModel
    @Environment(\.dismiss) private var dismiss

    private var filter: MeetFilter { app.preferences.meetFilter }

    var body: some View {
        let options = filter.options(for: app.meets, locale: app.locale)
        NavigationStack {
            List {
                if !options.clubs.isEmpty {
                    Section(Native.filterClub) {
                        ForEach(options.clubs, id: \.self) { club in
                            row(club, checked: filter.has(club: club)) { $0.toggle(club: club) }
                        }
                    }
                }
                if !options.countries.isEmpty {
                    Section(Native.filterCountry) {
                        ForEach(options.countries, id: \.self) { code in
                            row(
                                app.locale.localizedString(forRegionCode: code) ?? code,
                                checked: filter.has(country: code)
                            ) { $0.toggle(country: code) }
                        }
                    }
                }
                if !options.provinces.isEmpty {
                    Section(Native.filterProvince) {
                        ForEach(options.provinces, id: \.self) { p in
                            row(p.label(locale: app.locale), checked: filter.has(province: p)) {
                                $0.toggle(province: p)
                            }
                        }
                    }
                }
                Section {
                    Button(Native.filterClear, role: .destructive) {
                        app.setMeetFilter(MeetFilter())
                    }
                    .frame(maxWidth: .infinity)
                    .disabled(!filter.isActive)
                }
            }
            .navigationTitle(Native.meetFilter)
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
            .sensoryFeedback(.selection, trigger: filter)
        }
    }

    /// A checkable row, the way Settings lists a multiple choice: the whole row
    /// is the button, the checkmark trails, and the choice is announced (X-06).
    private func row(_ text: String, checked: Bool, toggle: @escaping (inout MeetFilter) -> Void) -> some View {
        Button {
            var f = filter
            toggle(&f)
            app.setMeetFilter(f)
        } label: {
            HStack {
                Text(text).foregroundStyle(.primary)
                Spacer()
                if checked {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(checked ? .isSelected : [])
    }
}
