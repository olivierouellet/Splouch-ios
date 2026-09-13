import Testing
@testable import SplouchCore

@Suite struct RaceClockTests {
    let t0 = ContinuousClock.now

    @Test func parsesEveryConsoleShape() {
        #expect(RaceClock.parseHundredths("1:05.23") == 6523)
        #expect(RaceClock.parseHundredths("59.99") == 5999)
        #expect(RaceClock.parseHundredths("5.23") == 523)
        #expect(RaceClock.parseHundredths(" 12:00.00 ") == 72000)
    }

    @Test func rejectsNonClockStrings() {
        for bad in ["", "abc", "1:05", "1:05.2", "1:05.234", "105.23", ":05.23", "1:5.2x", "-1.00", "1.2.3"] {
            #expect(RaceClock.parseHundredths(bad) == nil, "\(bad)")
        }
    }

    @Test func formatsTenthsNotHundredths() {
        #expect(RaceClock.formatTenths(6523) == "1:05.2")
        #expect(RaceClock.formatTenths(523) == "5.2")
        #expect(RaceClock.formatTenths(5999) == "59.9")
        #expect(RaceClock.formatTenths(6000) == "1:00.0")
        #expect(RaceClock.formatTenths(0) == "0.0")
        #expect(RaceClock.formatTenths(-5) == "0.0")
    }

    @Test func idleUntilRebased() {
        let c = RaceClock()
        #expect(!c.isRunning)
        #expect(c.reading(at: t0) == nil)
    }

    @Test func ticksForwardFromTheBase() {
        var c = RaceClock()
        let accepted = c.rebase("25.00", at: t0)
        #expect(accepted)
        #expect(c.reading(at: t0) == .ticking("25.0"))
        #expect(c.reading(at: t0 + .milliseconds(1_540)) == .ticking("26.5"))
        #expect(c.reading(at: t0 + .seconds(35)) == .frozen("31.0"))
    }

    @Test func rebaseIsHardNeverEased() {
        var c = RaceClock()
        c.rebase("25.00", at: t0)
        // The relay's next value is behind where the local tick had reached.
        c.rebase("26.00", at: t0 + .seconds(2))
        #expect(c.reading(at: t0 + .seconds(2)) == .ticking("26.0"))
    }

    @Test func unparseableRebaseIsIgnored() {
        var c = RaceClock()
        c.rebase("25.00", at: t0)
        let accepted = c.rebase("garbage", at: t0 + .seconds(1))
        #expect(!accepted)
        #expect(c.reading(at: t0 + .seconds(1)) == .ticking("26.0"))
    }

    @Test func freezesForwardAfterThreeSyncIntervals() {
        var c = RaceClock()
        c.rebase("1:00.00", at: t0)
        #expect(c.reading(at: t0 + .seconds(6)) == .ticking("1:06.0"))
        // Past the window: frozen at base + 6s, not back at the base.
        #expect(c.reading(at: t0 + .seconds(6) + .milliseconds(1)) == .frozen("1:06.0"))
        #expect(c.reading(at: t0 + .seconds(60)) == .frozen("1:06.0"))
    }

    @Test func stopForgetsTheBase() {
        var c = RaceClock()
        c.rebase("25.00", at: t0)
        c.stop()
        #expect(!c.isRunning)
        #expect(c.reading(at: t0 + .seconds(1)) == nil)
    }

    @Test func staleWindowIsThreeSyncIntervals() {
        #expect(RaceClock.staleAfter == RaceClock.syncInterval * 3)
        #expect(RaceClock.tickInterval == .milliseconds(100))
    }
}
