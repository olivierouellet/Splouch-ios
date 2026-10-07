import Testing

@testable import SplouchUI

/// P-03's live dot: every row breathes at one pace, but rows close together
/// never breathe together.
@Suite struct LiveDotTests {
    /// The widest gap between two rows' breaths over one full cycle.
    private func spread(_ a: Int, _ b: Int) -> Double {
        stride(from: 0.0, to: 1.7, by: 0.01)
            .map { abs(MeetCard.breath(at: $0, rank: a) - MeetCard.breath(at: $0, rank: b)) }
            .max() ?? 0
    }

    @Test func aBreathRunsFromFullToFaintAndBack() {
        let samples = stride(from: 0.0, to: 1.7, by: 0.01).map { MeetCard.breath(at: $0, rank: 0) }
        #expect(samples.min()! >= 0 && samples.min()! < 0.01)
        #expect(samples.max()! <= 1 && samples.max()! > 0.99)
        #expect(abs(MeetCard.breath(at: 0, rank: 3) - MeetCard.breath(at: 1.7, rank: 3)) < 1e-9)
    }

    @Test func rowsCloseTogetherAreNeverInStep() {
        for rank in 0..<60 {
            #expect(spread(rank, rank + 1) > 0.9)
            #expect(spread(rank, rank + 2) > 0.6)
        }
    }
}
