import XCTest
@testable import CadenceCore

final class RepPatternTests: XCTestCase {

    // MARK: - No data

    func testNoHistoryReturnsNil() {
        XCTAssertNil(RepPattern.guess(setIndex: 1, currentSessionReps: [], priorSessionLadders: []))
    }

    func testSetZeroWithNoDataReturnsNil() {
        XCTAssertNil(RepPattern.guess(setIndex: 0, currentSessionReps: [], priorSessionLadders: []))
    }

    // MARK: - Session-in-progress (current reps already cover set index)

    func testReturnsCurrentValueWhenAlreadyLogged() {
        let result = RepPattern.guess(setIndex: 1, currentSessionReps: [12, 10], priorSessionLadders: [])
        XCTAssertEqual(result, 10)
    }

    // MARK: - Flat pattern

    func testFlatPatternFromCurrentSession() {
        let result = RepPattern.guess(setIndex: 2, currentSessionReps: [20, 20], priorSessionLadders: [])
        XCTAssertEqual(result, 20)
    }

    func testFlatPatternNeedsAtLeastTwoReps() {
        let result = RepPattern.guess(setIndex: 1, currentSessionReps: [12], priorSessionLadders: [])
        XCTAssertNil(result)
    }

    // MARK: - Arithmetic progression

    func testDescendingPattern() {
        // 12, 10 → guess 8
        let result = RepPattern.guess(setIndex: 2, currentSessionReps: [12, 10], priorSessionLadders: [])
        XCTAssertEqual(result, 8)
    }

    func testAscendingPattern() {
        // 8, 10 → guess 12
        let result = RepPattern.guess(setIndex: 2, currentSessionReps: [8, 10], priorSessionLadders: [])
        XCTAssertEqual(result, 12)
    }

    func testDescendingWithNegativeFloor() {
        // 3, 2 → guesses 1, 3, 1 → guesses 0 (below floor) → nil
        let result = RepPattern.guess(setIndex: 3, currentSessionReps: [3, 2, 1], priorSessionLadders: [])
        XCTAssertNil(result)
    }

    // MARK: - Prior session pattern matching

    func testMatchesPriorSessionPrefix() {
        // Current: [12, 10], prior: [12, 10, 8] → guess set 2 as 8
        let result = RepPattern.guess(
            setIndex: 2,
            currentSessionReps: [12, 10],
            priorSessionLadders: [[12, 10, 8]]
        )
        XCTAssertEqual(result, 8)
    }

    func testMostCommonPriorLadderWins() {
        let result = RepPattern.guess(
            setIndex: 2,
            currentSessionReps: [],
            priorSessionLadders: [[12, 10, 10], [12, 10, 8], [12, 10, 8], [12, 10, 8]]
        )
        // [12, 10, 8] appears 3 times out of 4 → confidence 0.75 → use it
        XCTAssertEqual(result, 8)
    }

    func testPriorConsensusNeedsFiftyPercent() {
        let result = RepPattern.guess(
            setIndex: 2,
            currentSessionReps: [],
            priorSessionLadders: [[12, 10, 10], [12, 10, 8], [12, 10, 6], [12, 10, 5]]
        )
        // No ladder appears >50%, but most recent is [12, 10, 5] as last resort
        XCTAssertEqual(result, 5)
    }

    func testPrefixMatchFromMultiplePriors() {
        let result = RepPattern.guess(
            setIndex: 2,
            currentSessionReps: [12],
            priorSessionLadders: [[12, 10, 8], [12, 8, 6], [10, 8, 6]]
        )
        // Two prior sessions start with 12: [12, 10, 8] and [12, 8, 6]
        // Most common matching prefix ladder: tie on count, first wins
        XCTAssertEqual(result, 8)
    }

    // MARK: - Last resort fallback

    func testFallsBackToMostRecentPrior() {
        let result = RepPattern.guess(
            setIndex: 2,
            currentSessionReps: [],
            priorSessionLadders: [[10, 10, 10], [20, 15, 12]]
        )
        // No consensus (>50%), so use last ([20, 15, 12]) set index 2 = 12
        XCTAssertEqual(result, 12)
    }

    func testMostRecentPriorShorterThanSetIndexReturnsNil() {
        let result = RepPattern.guess(
            setIndex: 3,
            currentSessionReps: [],
            priorSessionLadders: [[12, 10, 8]]
        )
        // Only 3 sets in prior, set index 3 is out of bounds → nil
        XCTAssertNil(result)
    }

    // MARK: - Mixed session-in-progress + prior

    func testCurrentSessionPrefixMatchesPrior() {
        // Current: [12], prior offers two matching prefixes → 10 (tie, first wins)
        let result = RepPattern.guess(
            setIndex: 1,
            currentSessionReps: [12],
            priorSessionLadders: [[12, 10, 8], [12, 8, 6]]
        )
        XCTAssertEqual(result, 10)
    }

    func testSingleExactPrefixMatchFromPrior() {
        // Only one prior session matches the prefix → use its value
        let result = RepPattern.guess(
            setIndex: 1,
            currentSessionReps: [12],
            priorSessionLadders: [[12, 10, 8], [10, 8, 6]]
        )
        XCTAssertEqual(result, 10)
    }
}
