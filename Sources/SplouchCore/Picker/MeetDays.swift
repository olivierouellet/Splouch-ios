import Foundation

/// P-01: the meet list as days, each named once above its meets, so no card
/// repeats its date.
public struct MeetDay: Sendable, Equatable, Identifiable {
    /// `YYYY-MM-DD`, or `""` for the meets with no date.
    public let date: String
    public let meets: [MeetSummary]
    public var id: String { date }

    /// The server sends meets by date then city (api.md §5.6), which this
    /// keeps. Sorted again by date only, stably, so a server from before that
    /// order still gives one heading per day; an undated meet goes last.
    public static func group(_ meets: [MeetSummary]) -> [MeetDay] {
        let ordered = meets.enumerated().sorted { a, b in
            let (x, y) = (a.element.meetDate, b.element.meetDate)
            if x != y { return y.isEmpty || (!x.isEmpty && x < y) }
            return a.offset < b.offset
        }
        var days: [MeetDay] = []
        for (_, meet) in ordered {
            if let last = days.last, last.date == meet.meetDate {
                days[days.count - 1] = MeetDay(date: last.date, meets: last.meets + [meet])
            } else {
                days.append(MeetDay(date: meet.meetDate, meets: [meet]))
            }
        }
        return days
    }

    /// `Tuesday, October 6` in the reader's language, the year only when it
    /// is not this one; nil for no date or one that does not parse, which the
    /// picker heads with the server's `date_unknown` or shows as sent.
    public func heading(locale: Locale = .current, now: Date = .now) -> String? {
        let parts = date.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        guard let day = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
        else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate(
            calendar.component(.year, from: now) == parts[0] ? "EEEEMMMMd" : "EEEEMMMMdy")
        return formatter.string(from: day)
    }
}

extension MeetSummary {
    /// P-01: the card's second line — city, state/province code, country code
    /// (`Montréal · QC · CA`). A state/province the app does not know is shown
    /// as sent. What `filter` narrows to exactly one is left off: with only
    /// Canada chosen, no card says `CA`.
    public func place(filter: MeetFilter = MeetFilter()) -> [String] {
        let code = Subdivisions.lookup(country: country, province: province)?.code ?? province
        return [
            location,
            filter.pinsProvince ? "" : code,
            filter.pinsCountry ? "" : country.uppercased(),
        ].filter { !$0.isEmpty }
    }
}

extension MeetFilter {
    /// Countries and provinces all of one country: every meet shown is in it,
    /// clubs only narrowing.
    public var pinsCountry: Bool { Set(countries).union(provinces.map(\.country)).count == 1 }

    /// One state/province, and no other country: every meet shown is in it,
    /// however many spellings of it the list held.
    public var pinsProvince: Bool {
        Set(provinces.map(\.key)).count == 1 && countries.subtracting(provinces.map(\.country)).isEmpty
    }
}
