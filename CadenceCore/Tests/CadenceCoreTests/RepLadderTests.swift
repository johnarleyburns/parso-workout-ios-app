import Testing
@testable import CadenceCore

/// P1 (issue 2) — goal-specific descending rep ladders. The coach must prescribe a
/// productive pyramid across the goal's rep range, not flatten every set to the low
/// bound. Cited to the load/rep continuum (Schoenfeld et al. 2021).
struct RepLadderTests {

    // MARK: hypertrophy (6…12) — descending by 2 from the top

    @Test func hypertrophyThreeSets() {
        #expect(RepLadder.ladder(for: .hypertrophy, sets: 3) == [12, 10, 8])
    }

    @Test func hypertrophyFourSets() {
        #expect(RepLadder.ladder(for: .hypertrophy, sets: 4) == [12, 10, 8, 6])
    }

    @Test func hypertrophyTwoSets() {
        #expect(RepLadder.ladder(for: .hypertrophy, sets: 2) == [12, 10])
    }

    @Test func hypertrophyFiveSetsClampsAtFloor() {
        // Never drops below the low bound (6).
        #expect(RepLadder.ladder(for: .hypertrophy, sets: 5) == [12, 10, 8, 6, 6])
    }

    // MARK: strength (3…5) — heavy top-set hold

    @Test func strengthThreeSets() {
        #expect(RepLadder.ladder(for: .strength, sets: 3) == [5, 5, 3])
    }

    @Test func strengthFourSets() {
        #expect(RepLadder.ladder(for: .strength, sets: 4) == [5, 5, 3, 3])
    }

    // MARK: endurance (15…20) — descending, clamped

    @Test func enduranceThreeSets() {
        #expect(RepLadder.ladder(for: .endurance, sets: 3) == [20, 18, 16])
    }

    @Test func enduranceFourSetsClampsAtFloor() {
        #expect(RepLadder.ladder(for: .endurance, sets: 4) == [20, 18, 16, 15])
    }

    // MARK: explicit high-rep ranges — descending by 10 from the top

    @Test func highRepRangeDescendsByTen() {
        #expect(RepLadder.ladder(low: 24, high: 40, sets: 3) == [40, 30, 24])
        #expect(RepLadder.ladder(low: 20, high: 40, sets: 3) == [40, 30, 20])
    }

    @Test func nonHighRepExplicitRangeKeepsTwoRepDrops() {
        #expect(RepLadder.ladder(low: 6, high: 12, sets: 3) == [12, 10, 8])
    }

    // MARK: edges

    @Test func zeroSetsIsEmpty() {
        #expect(RepLadder.ladder(for: .hypertrophy, sets: 0) == [])
        #expect(RepLadder.ladder(for: .strength, sets: -1) == [])
    }

    @Test func singleSetIsMidpointNotFloor() {
        // Hypertrophy midpoint of 6…12 is 9 — a productive dose, not the 6 floor.
        #expect(RepLadder.ladder(for: .hypertrophy, sets: 1) == [9])
        #expect(RepLadder.ladder(for: .strength, sets: 1) == [4])
    }

    @Test func everyValueWithinRange() {
        for goal in TrainingGoal.allCases {
            for count in 1...8 {
                for reps in RepLadder.ladder(for: goal, sets: count) {
                    #expect(goal.repRange.contains(reps),
                                  "\(goal) sets=\(count) produced \(reps) outside \(goal.repRange)")
                }
            }
        }
    }

    @Test func laddersAreNonAscending() {
        for goal in TrainingGoal.allCases {
            let ladder = RepLadder.ladder(for: goal, sets: 4)
            for (a, b) in zip(ladder, ladder.dropFirst()) {
                #expect(a >= b, "\(goal) ladder should be non-ascending: \(ladder)")
            }
        }
    }
}
