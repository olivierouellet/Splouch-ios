import Foundation

/// P-21: the picker's own filter — by country, state/province and club — kept by
/// the app across launches and servers. A spectator follows one region or club
/// for a season, so unlike the schedule's (S-20) it is stored.
///
/// Several values per facet: a meet passes a facet when it holds any of its
/// values (OR), and passes the filter when it passes every active facet (AND).
/// A meet whose field is empty fails that facet while it is active.
public struct MeetFilter: Sendable, Codable, Equatable {
    /// ISO 3166-1 alpha-2, upper-cased.
    public var countries: Set<String>
    public var provinces: Set<Province>
    /// The organizer as first chosen; compared folded, as S-09 compares a club.
    public var clubs: Set<String>

    /// A state or province is only one with its country: `ON` is not unique the
    /// world over, and the sheet names it with its country.
    public struct Province: Sendable, Codable, Hashable {
        public var country: String
        public var name: String

        public init(country: String, name: String) {
            self.country = country.uppercased()
            self.name = name
        }

        /// What two spellings of one province share.
        var key: String { country + "/" + SuggestionIndex.fold(name) }
    }

    public init(countries: Set<String> = [], provinces: Set<Province> = [], clubs: Set<String> = []) {
        self.countries = countries
        self.provinces = provinces
        self.clubs = clubs
    }

    public var isActive: Bool { !countries.isEmpty || !provinces.isEmpty || !clubs.isEmpty }

    public func matches(_ meet: MeetSummary) -> Bool {
        if !countries.isEmpty, !countries.contains(meet.country.uppercased()) { return false }
        if !provinces.isEmpty {
            let key = Province(country: meet.country, name: meet.province).key
            if meet.province.isEmpty || !provinces.contains(where: { $0.key == key }) { return false }
        }
        if !clubs.isEmpty {
            let key = SuggestionIndex.fold(meet.organizer)
            if key.isEmpty || !clubs.contains(where: { SuggestionIndex.fold($0) == key }) { return false }
        }
        return true
    }

    /// The meets the filter leaves, in the server's order.
    public func apply(_ meets: [MeetSummary]) -> [MeetSummary] {
        isActive ? meets.filter(matches) : meets
    }

    // MARK: - Choosing

    public func has(country: String) -> Bool { countries.contains(country.uppercased()) }
    public func has(province: Province) -> Bool { provinces.contains { $0.key == province.key } }
    public func has(club: String) -> Bool {
        let key = SuggestionIndex.fold(club)
        return clubs.contains { SuggestionIndex.fold($0) == key }
    }

    /// Taking a country away takes its provinces with it: the sheet no longer
    /// lists them, and kept they would hide every meet of the countries left.
    public mutating func toggle(country: String) {
        let code = country.uppercased()
        if countries.remove(code) == nil {
            countries.insert(code)
        } else {
            provinces = provinces.filter { $0.country != code }
        }
    }

    public mutating func toggle(province: Province) {
        if let held = provinces.first(where: { $0.key == province.key }) {
            provinces.remove(held)
        } else {
            provinces.insert(province)
        }
    }

    public mutating func toggle(club: String) {
        let key = SuggestionIndex.fold(club)
        if let held = clubs.first(where: { SuggestionIndex.fold($0) == key }) {
            clubs.remove(held)
        } else {
            clubs.insert(club)
        }
    }

    // MARK: - What the sheet offers

    /// The values to offer: those the list holds, plus any chosen value it no
    /// longer holds, so it can still be unchecked. Provinces only of the chosen
    /// countries once one is chosen. Each sorted by what the reader sees.
    public struct Options: Sendable, Equatable {
        public var countries: [String]
        public var provinces: [Province]
        public var clubs: [String]
    }

    public func options(for meets: [MeetSummary], locale: Locale = .current) -> Options {
        func name(_ code: String) -> String { locale.localizedString(forRegionCode: code) ?? code }
        func sorted<T>(_ items: [T], by text: (T) -> String) -> [T] {
            items.sorted { text($0).localizedStandardCompare(text($1)) == .orderedAscending }
        }

        var codes = Set(meets.map { $0.country.uppercased() }.filter { !$0.isEmpty })
        codes.formUnion(countries)

        var provinceByKey: [String: Province] = [:]
        for p in provinces { provinceByKey[p.key] = p }
        for m in meets where !m.province.isEmpty {
            let p = Province(country: m.country, name: m.province)
            if provinceByKey[p.key] == nil { provinceByKey[p.key] = p }
        }
        var shownProvinces = Array(provinceByKey.values)
        if !countries.isEmpty { shownProvinces = shownProvinces.filter { countries.contains($0.country) } }

        var clubByKey: [String: String] = [:]
        for c in clubs { clubByKey[SuggestionIndex.fold(c)] = c }
        for m in meets where !m.organizer.isEmpty {
            let key = SuggestionIndex.fold(m.organizer)
            if !key.isEmpty, clubByKey[key] == nil { clubByKey[key] = m.organizer }
        }

        return Options(
            countries: sorted(Array(codes), by: name),
            provinces: sorted(shownProvinces) { "\($0.name) \(name($0.country))" },
            clubs: sorted(Array(clubByKey.values)) { $0 })
    }
}

extension MeetFilter.Province {
    /// `QC, Canada`, as P-01 names a meet's region.
    public func label(locale: Locale = .current) -> String {
        let country = locale.localizedString(forRegionCode: country) ?? country
        return country.isEmpty ? name : "\(name), \(country)"
    }
}
