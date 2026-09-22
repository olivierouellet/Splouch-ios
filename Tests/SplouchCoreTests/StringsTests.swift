import Testing
@testable import SplouchCore

@Suite struct EventNameTests {
    let es: [String: String] = ["unit": "m", "separator": "  —  ", "backstroke": "espalda", "girls": "Niñas",
                                "relay": "Relevos", "freestyle": "libre", "mixed": "Mixto", "open": "Abierto"]

    @Test func composesFromParts() {
        let p = EventNameParts(raw: "200 Backstroke Girls 12 & Under", dist: "200", stroke: "backstroke", gender: "girls", age: "< 12")
        #expect(EventName.compose(p, vocab: es) == "200 m espalda  —  Niñas < 12")
    }

    @Test func relayAndAgeKey() {
        let p = EventNameParts(dist: "4x50", stroke: "freestyle", relay: true, gender: "mixed", ageKey: "open")
        #expect(EventName.compose(p, vocab: es) == "4x50 m libre Relevos  —  Mixto Abierto")
    }

    @Test func unknownKeysRenderAsThemselves() {
        let p = EventNameParts(dist: "100", stroke: "sidestroke", gender: "boys")
        #expect(EventName.compose(p, vocab: es) == "100 m sidestroke  —  boys")
    }

    @Test func fallsBackToRawThenName() {
        let hand = EventNameParts(raw: "Club Handicap Final")
        #expect(EventName.compose(hand, vocab: es) == "Club Handicap Final")
        #expect(EventName.compose(EventNameParts(), vocab: es) == "")
        #expect(EventName.compose(nil, vocab: es) == "")
        #expect(EventName.compose(EventNameParts(dist: "50"), vocab: nil) == "")
        #expect(EventName.resolve(eventName: "200 m dos", parts: nil, vocab: es) == "200 m dos")
        #expect(EventName.resolve(eventName: "200 m dos", parts: EventNameParts(dist: "200", stroke: "backstroke"), vocab: es) == "200 m espalda")
    }

    @Test func onlyRightSide() {
        #expect(EventName.compose(EventNameParts(gender: "girls"), vocab: es) == "Niñas")
    }

    /// T-11: a server whose `event_name` section is missing the two joining words
    /// still composes. `unit` and `separator` are the only vocabulary entries the
    /// client supplies a default for, because without them the name would read
    /// "200 backstroke" with no unit and the two halves would run together — the
    /// same defaults `ws.js` carries, so a phone and the web page agree.
    @Test func theJoiningWordsHaveDefaultsWhenTheVocabularyOmitsThem() {
        let thin: [String: String] = ["backstroke": "dos", "girls": "Filles"]
        let p = EventNameParts(raw: "200 Back Girls", dist: "200", stroke: "backstroke", gender: "girls")
        #expect(EventName.compose(p, vocab: thin) == "200 m dos  \u{2014}  Filles")

        // And a vocabulary that names them is still preferred over the defaults.
        let named = thin.merging(["unit": "v", "separator": " / "]) { $1 }
        #expect(EventName.compose(p, vocab: named) == "200 v dos / Filles")
    }

    /// An empty `relay` word is not a word: the flag is set but there is nothing
    /// to show, so the name composes without it rather than with a blank slot.
    @Test func anEmptyRelayWordIsNotAppended() {
        let vocab = es.merging(["relay": ""]) { $1 }
        let p = EventNameParts(dist: "4x50", stroke: "freestyle", relay: true)
        #expect(EventName.compose(p, vocab: vocab) == "4x50 m libre")
    }
}

@Suite struct StringTableTests {
    let english = I18nBundle(lang: "en", mobile: ["scoreboard": "Scoreboard", "results": "Results", "brand_new": "New"],
                             display: ["retrying": "retrying"],
                             labels: ["short": ["event": "EV", "heat": "HT", "lane": "LN"], "long": ["event": "EVENT", "heat": "HEAT", "lane": "LN"]],
                             eventName: ["unit": "m", "girls": "Girls", "boys": "Boys"])
    let builtInFr = I18nBundle(lang: "fr", mobile: ["scoreboard": "Tableau"], labels: ["short": ["event": "ÉP"]], eventName: ["girls": "Filles"])
    let serverFr = I18nBundle(lang: "fr", mobile: ["results": "Résultats", "scoreboard": ""], labels: ["long": ["event": "ÉPREUVE"]], eventName: ["boys": "Garçons"])

    @Test func resolutionOrder() {
        let t = StringTable(language: "fr", server: serverFr, builtIn: builtInFr, english: english)
        #expect(t.mobile("results") == "Résultats")      // server
        #expect(t.mobile("scoreboard") == "Tableau")     // server blank → built-in
        #expect(t.mobile("brand_new") == "New")          // English floor
        #expect(t.mobile("unheard_of") == "unheard_of")  // the key itself
        #expect(t.display("retrying") == "retrying")
    }

    @Test func vocabularyAndLabelsMergePerKey() {
        let t = StringTable(language: "fr", server: serverFr, builtIn: builtInFr, english: english)
        #expect(t.eventVocabulary == ["unit": "m", "girls": "Filles", "boys": "Garçons"])
        #expect(t.labels(.short) == ["event": "ÉP", "heat": "HT", "lane": "LN"])
        #expect(t.labels(.long) == ["event": "ÉPREUVE", "heat": "HEAT", "lane": "LN"])
    }

    @Test func offlineFirstLaunchUsesBuiltIns() {
        let t = StringTable(language: "fr", server: nil, builtIn: builtInFr, english: english)
        #expect(t.mobile("scoreboard") == "Tableau")
        #expect(t.mobile("results") == "Results")
    }
}

@Suite struct LabelResolverTests {
    let english = I18nBundle(lang: "en",
                             labels: ["short": ["event": "EV", "heat": "HT", "lane": "LN", "place": "PL"],
                                      "long": ["event": "EVENT", "heat": "HEAT", "lane": "LN", "place": "PL"]])
    var settings: MeetSettings {
        MeetSettings(locale: "en", labels: ["event": "ÉP", "heat": "SÉR", "lane": "CL"], labelStyle: "short")
    }

    @Test func noTableRendersTheServersLabelsAsSent() {
        #expect(LabelResolver.labels(settings: settings, language: "fr", style: .long, table: nil) == settings.labels)
    }

    @Test func chosenStyleUsesTheI18nTableAsServed() {
        let table = StringTable(language: "en", english: english)
        // The server's long table already keeps the narrow columns short (T-09);
        // the app renders it as given.
        let long = LabelResolver.labels(settings: settings, language: nil, style: .long, table: table)
        #expect(long == ["event": "EVENT", "heat": "HEAT", "lane": "LN", "place": "PL"])
        let short = LabelResolver.labels(settings: settings, language: nil, style: .short, table: table)
        #expect(short == ["event": "EV", "heat": "HT", "lane": "LN", "place": "PL"])
    }

    @Test func theOperatorsStyleNoLongerSelectsTheTable() {
        let table = StringTable(language: "en", english: english)
        // The device's style is the only one that counts now: a meet served as
        // `short` still renders long for a device set to long.
        var s = settings
        s.labelStyle = "short"
        #expect(LabelResolver.labels(settings: s, language: "en", style: .long, table: table)["event"] == "EVENT")
        s.labelStyle = "long"
        #expect(LabelResolver.labels(settings: s, language: "en", style: .short, table: table)["event"] == "EV")
    }

    @Test func emptyTableFallsBackToSettings() {
        let table = StringTable(language: "xx", english: I18nBundle(lang: "en"))
        #expect(LabelResolver.labels(settings: settings, language: "xx", style: .long, table: table) == settings.labels)
    }
}

@Suite struct ThemeTests {
    @Test func missingKeysFallBackToDefaults() {
        let c = ThemeColors(["bg": "#000000", "time": " "])
        #expect(c.bg == "#000000")
        #expect(c.time == "#FFD700")
        #expect(c.scheduleEvent == "#3b9eff")
        #expect(ThemeColors() == ThemeColors([:]))
    }

    @Test func fontsHaveThreeRoles() {
        let f = ThemeFonts(["family": "Orbitron"])
        #expect(f.family == "Orbitron")
        #expect(f.digits == "DSEG7Classic")
        #expect(f.timing == "Overpass Mono")
    }

    @Test func everyContractKeyHasADefault() {
        for k in ["bg", "header_bg", "header_border", "header_label", "header_value", "th_text", "th_bg",
                  "row_odd", "row_even", "row_text", "time", "delta_better", "delta_worse",
                  "schedule_event", "schedule_time", "schedule_name", "schedule_club"] {
            #expect(ThemeColors.defaults[k] != nil, "\(k)")
        }
    }
}
