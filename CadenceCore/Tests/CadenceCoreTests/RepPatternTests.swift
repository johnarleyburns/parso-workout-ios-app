import Testing
@testable import CadenceCore

struct RepPatternTests {

    // MARK: - No data

    @Test func noHistoryReturnsNil() {
        #expect(RepPattern.guess(setIndex: 1, currentSessionReps: [], priorSessionLadders: []) == nil)
    }

    @Test func setZeroWithNoDataReturnsNil() {
        #expect(RepPattern.guess(setIndex: 0, currentSessionReps: [], priorSessionLadders: []) == nil)
    }

    // MARK: - Session-in-progress (current reps already cover set index)

    @Test func returnsCurrentValueWhenAlreadyLogged() {
        let result = RepPattern.guess(setIndex: 1, currentSessionReps: [12, 10], priorSessionLadders: [])
        #expect(result == 10)
    }

    // MARK: - Flat pattern

    @Test func flatPatternFromCurrentSession() {
        let result = RepPattern.guess(setIndex: 2, currentSessionReps: [20, 20], priorSessionLadders: [])
        #expect(result == 20)
    }

    @Test func flatPatternNeedsAtLeastTwoReps() {
        let result = RepPattern.guess(setIndex: 1, currentSessionReps: [12], priorSessionLadders: [])
        #expect(result == nil)
    }

    // MARK: - Arithmetic progression

    @Test func descendingPattern() {
        // 12, 10 → guess 8
        let result = RepPattern.guess(setIndex: 2, currentSessionReps: [12, 10], priorSessionLadders: [])
        #expect(result == 8)
    }

    @Test func ascendingPattern() {
        // 8, 10 → guess 12
        let result = RepPattern.guess(setIndex: 2, currentSessionReps: [8, 10], priorSessionLadders: [])
        #expect(result == 12)
    }

    @Test func descendingWithNegativeFloor() {
        // 3, 2 → guesses 1, 3, 1 → guesses 0 (below floor) → nil
        let result = RepPattern.guess(setIndex: 3, currentSessionReps: [3, 2, 1], priorSessionLadders: [])
        #expect(result == nil)
    }

    // MARK: - Prior session pattern matching

    @Test func matchesPriorSessionPrefix() {
        // Current: [12, 10], prior: [12, 10, 8] → guess set 2 as 8
        let result = RepPattern.guess(
            setIndex: 2,
            currentSessionReps: [12, 10],
            priorSessionLadders: [[12, 10, 8]]
        )
        #expect(result == 8)
    }

    @Test func mostCommonPriorLadderWins() {
        let result = RepPattern.guess(
            setIndex: 2,
            currentSessionReps: [],
            priorSessionLadders: [[12, 10, 10], [12, 10, 8], [12, 10, 8], [12, 10, 8]]
        )
        // [12, 10, 8] appears 3 times out of 4 → confidence 0.75 → use it
        #expect(result == 8)
    }

    @Test func priorConsensusNeedsFiftyPercent() {
        let result = RepPattern.guess(
            setIndex: 2,
            currentSessionReps: [],
            priorSessionLadders: [[12, 10, 10], [12, 10, 8], [12, 10, 6], [12, 10, 5]]
        )
        // No ladder appears >50%, but most recent is [12, 10, 5] as last resort
        #expect(result == 5)
    }

    @Test func prefixMatchFromMultiplePriors() {
        let result = RepPattern.guess(
            setIndex: 2,
            currentSessionReps: [12],
            priorSessionLadders: [[12, 10, 8], [12, 8, 6], [10, 8, 6]]
        )
        // Two prior sessions start with 12: [12, 10, 8] and [12, 8, 6]
        // Most common matching prefix ladder: tie on count, first wins
        #expect(result == 8)
    }

    // MARK: - Last resort fallback

    @Test func fallsBackToMostRecentPrior() {
        let result = RepPattern.guess(
            setIndex: 2,
            currentSessionReps: [],
            priorSessionLadders: [[10, 10, 10], [20, 15, 12]]
        )
        // No consensus (>50%), so use last ([20, 15, 12]) set index 2 = 12
        #expect(result == 12)
    }

    @Test func mostRecentPriorShorterThanSetIndexReturnsNil() {
        let result = RepPattern.guess(
            setIndex: 3,
            currentSessionReps: [],
            priorSessionLadders: [[12, 10, 8]]
        )
        // Only 3 sets in prior, set index 3 is out of bounds → nil
        #expect(result == nil)
    }

    // MARK: - Mixed session-in-progress + prior

    @Test func currentSessionPrefixMatchesPrior() {
        // Current: [12], prior offers two matching prefixes → 10 (tie, first wins)
        let result = RepPattern.guess(
            setIndex: 1,
            currentSessionReps: [12],
            priorSessionLadders: [[12, 10, 8], [12, 8, 6]]
        )
        #expect(result == 10)
    }

    @Test func singleExactPrefixMatchFromPrior() {
        // Only one prior session matches the prefix → use its value
        let result = RepPattern.guess(
            setIndex: 1,
            currentSessionReps: [12],
            priorSessionLadders: [[12, 10, 8], [10, 8, 6]]
        )
        #expect(result == 10)
    }
}
