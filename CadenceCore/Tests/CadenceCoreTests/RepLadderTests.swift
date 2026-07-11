import XCTest
@testable import CadenceCore

/// P1 (issue 2) — goal-specific descending rep ladders. The coach must prescribe a
/// productive pyramid across the goal's rep range, not flatten every set to the low
/// bound. Cited to the load/rep continuum (Schoenfeld et al. 2021).
final class RepLadderTests: XCTestCase {

    // MARK: hypertrophy (6…12) — descending by 2 from the top

    func testHypertrophyThreeSets() {
        XCTAssertEqual(RepLadder.ladder(for: .hypertrophy, sets: 3), [12, 10, 8])
    }

    func testHypertrophyFourSets() {
        XCTAssertEqual(RepLadder.ladder(for: .hypertrophy, sets: 4), [12, 10, 8, 6])
    }

    func testHypertrophyTwoSets() {
        XCTAssertEqual(RepLadder.ladder(for: .hypertrophy, sets: 2), [12, 10])
    }

    func testHypertrophyFiveSetsClampsAtFloor() {
        // Never drops below the low bound (6).
        XCTAssertEqual(RepLadder.ladder(for: .hypertrophy, sets: 5), [12, 10, 8, 6, 6])
    }

    // MARK: strength (3…5) — heavy top-set hold

    func testStrengthThreeSets() {
        XCTAssertEqual(RepLadder.ladder(for: .strength, sets: 3), [5, 5, 3])
    }

    func testStrengthFourSets() {
        XCTAssertEqual(RepLadder.ladder(for: .strength, sets: 4), [5, 5, 3, 3])
    }

    // MARK: endurance (15…20) — descending, clamped

    func testEnduranceThreeSets() {
        XCTAssertEqual(RepLadder.ladder(for: .endurance, sets: 3), [20, 18, 16])
    }

    func testEnduranceFourSetsClampsAtFloor() {
        XCTAssertEqual(RepLadder.ladder(for: .endurance, sets: 4), [20, 18, 16, 15])
    }

    // MARK: edges

    func testZeroSetsIsEmpty() {
        XCTAssertEqual(RepLadder.ladder(for: .hypertrophy, sets: 0), [])
        XCTAssertEqual(RepLadder.ladder(for: .strength, sets: -1), [])
    }

    func testSingleSetIsMidpointNotFloor() {
        // Hypertrophy midpoint of 6…12 is 9 — a productive dose, not the 6 floor.
        XCTAssertEqual(RepLadder.ladder(for: .hypertrophy, sets: 1), [9])
        XCTAssertEqual(RepLadder.ladder(for: .strength, sets: 1), [4])
    }

    func testEveryValueWithinRange() {
        for goal in TrainingGoal.allCases {
            for count in 1...8 {
                for reps in RepLadder.ladder(for: goal, sets: count) {
                    XCTAssertTrue(goal.repRange.contains(reps),
                                  "\(goal) sets=\(count) produced \(reps) outside \(goal.repRange)")
                }
            }
        }
    }

    func testLaddersAreNonAscending() {
        for goal in TrainingGoal.allCases {
            let ladder = RepLadder.ladder(for: goal, sets: 4)
            for (a, b) in zip(ladder, ladder.dropFirst()) {
                XCTAssertGreaterThanOrEqual(a, b, "\(goal) ladder should be non-ascending: \(ladder)")
            }
        }
    }
}
