import Foundation

/// P-21: the picker's own filter — by country, state/province and club — kept by
/// the app across launches and servers. A spectator follows one region or club
/// for a season, so unlike the schedule's (S-20) it is stored.
///
/// Places, then clubs. A meet is in the chosen places when it is in a chosen
/// province, or in a chosen country none of whose provinces is chosen: a
/// province narrows its own country only (Canada, Québec and the United States
/// are Québec and the whole United States). Of the clubs, any one will do. A
/// meet passes when it passes both, each only while something in it is chosen.
/// A meet whose field is empty holds none of that field's values.
public struct MeetFilter: Sendable, Codable, Equatable {
    /// ISO 3166-1 alpha-2, upper-cased.
    public var countries: Set<String>
    public var provinces: Set<Province>
    /// The organizer as first chosen, or letters the spectator typed; compared
    /// by `clubKey`.
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

        /// What two spellings of one province share: its code when the app
        /// knows it, so `QC` and `Québec` are one choice; else the folded text.
        var key: String {
            if let known = Subdivisions.lookup(country: country, province: name) { return country + "#" + known.code }
            return country + "/" + SuggestionIndex.fold(name)
        }
    }

    public init(countries: Set<String> = [], provinces: Set<Province> = [], clubs: Set<String> = []) {
        self.countries = countries
        self.provinces = provinces
        self.clubs = clubs
    }

    public var isActive: Bool { !countries.isEmpty || !provinces.isEmpty || !clubs.isEmpty }

    public func matches(_ meet: MeetSummary) -> Bool {
        if !countries.isEmpty || !provinces.isEmpty {
            let code = meet.country.uppercased()
            let inProvince =
                !meet.province.isEmpty && has(province: Province(country: code, name: meet.province))
            let inCountry = !code.isEmpty && countries.contains(code) && !provinces.contains { $0.country == code }
            if !inProvince, !inCountry { return false }
        }
        if !clubs.isEmpty {
            if Self.clubKey(meet.organizer).isEmpty || !has(club: meet.organizer) { return false }
        }
        return true
    }

    /// Two spellings of one club: folded as S-09 folds, then letters and digits
    /// only, so `C.A.M.O.` is `CAMO`.
    static func clubKey(_ club: String) -> String {
        String(
            SuggestionIndex.fold(club).unicodeScalars.filter(CharacterSet.alphanumerics.contains).map(Character.init))
    }

    /// A club typed by the spectator, as kept: its official letters upper-cased,
    /// spaces and symbols dropped (` c.a.m.o ` → `CAMO`).
    public static func clubLetters(_ typed: String) -> String {
        String(typed.uppercased().filter { $0.isLetter || $0.isNumber })
    }

    /// The meets the filter leaves, in the server's order.
    public func apply(_ meets: [MeetSummary]) -> [MeetSummary] {
        isActive ? meets.filter(matches) : meets
    }

    // MARK: - Choosing

    public func has(country: String) -> Bool { countries.contains(country.uppercased()) }
    public func has(province: Province) -> Bool { provinces.contains { $0.key == province.key } }
    public func has(club: String) -> Bool {
        let key = Self.clubKey(club)
        return clubs.contains { Self.clubKey($0) == key }
    }

    /// Taking a country away takes its provinces with it: the sheet no longer
    /// lists them.
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
        let key = Self.clubKey(club)
        if let held = clubs.first(where: { Self.clubKey($0) == key }) {
            clubs.remove(held)
        } else {
            clubs.insert(club)
        }
    }

    /// Chooses the club whose official letters the spectator typed; letters
    /// already chosen, or none left once cleaned, change nothing.
    public mutating func add(clubLetters typed: String) {
        let letters = Self.clubLetters(typed)
        if !letters.isEmpty, !has(club: letters) { clubs.insert(letters) }
    }

    // MARK: - What the sheet offers

    /// The values to offer: clubs the list holds; every country and province
    /// the app knows, plus any other the list holds; plus any chosen value, so
    /// it can still be unchecked. Provinces only of the chosen countries once
    /// one is chosen, and any chosen one. Each sorted by what the reader sees.
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
        codes.formUnion(Subdivisions.countries)

        var provinceByKey: [String: Province] = [:]
        for p in provinces { provinceByKey[p.key] = p }
        for code in codes {
            for entry in Subdivisions.all(country: code) {
                let p = Province(country: code, name: entry.code)
                if provinceByKey[p.key] == nil { provinceByKey[p.key] = p }
            }
        }
        for m in meets where !m.province.isEmpty {
            let p = Province(country: m.country, name: m.province)
            if provinceByKey[p.key] == nil { provinceByKey[p.key] = p }
        }
        var shownProvinces = Array(provinceByKey.values)
        if !countries.isEmpty {
            shownProvinces = shownProvinces.filter { countries.contains($0.country) || has(province: $0) }
        }

        var clubByKey: [String: String] = [:]
        for c in clubs { clubByKey[Self.clubKey(c)] = c }
        for m in meets where !m.organizer.isEmpty {
            let key = Self.clubKey(m.organizer)
            if !key.isEmpty, clubByKey[key] == nil { clubByKey[key] = m.organizer }
        }

        return Options(
            countries: sorted(Array(codes), by: name),
            provinces: sorted(shownProvinces) { $0.label(locale: locale) },
            clubs: sorted(Array(clubByKey.values)) { $0 })
    }
}

extension MeetFilter.Province {
    /// `Québec, Canada`, as P-01 names a meet's region.
    public func label(locale: Locale = .current) -> String {
        let province = Subdivisions.name(country: country, province: name, locale: locale)
        let country = locale.localizedString(forRegionCode: country) ?? country
        return country.isEmpty ? province : "\(province), \(country)"
    }
}
