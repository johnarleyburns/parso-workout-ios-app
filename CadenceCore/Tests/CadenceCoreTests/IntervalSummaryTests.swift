import XCTest
@testable import CadenceCore

/// Interval history detail (feedback batch 4 / roadmap P5): deriving a
/// persistable `IntervalSummary` from a live plan, including ended-early rounds.
final class IntervalSummaryTests: XCTestCase {

    func testTabataStructure() {
        let plan = IntervalPlan.tabata() // 5:00 warm-up, 8×(20/10), 5:00 cool-down
        let s = IntervalSummary.from(plan: plan, elapsed: plan.totalDuration)
        XCTAssertEqual(s.protocolName, "Tabata")
        XCTAssertEqual(s.rounds, 8)
        XCTAssertEqual(s.workSeconds, 20)
        XCTAssertEqual(s.restSeconds, 10)
        XCTAssertEqual(s.warmupSeconds, 300)
        XCTAssertEqual(s.cooldownSeconds, 300)
        XCTAssertEqual(s.completedRounds, 8, "a full run completes every round")
    }

    func testBoxingHasNoWarmupOrCooldown() {
        let plan = IntervalPlan.boxing(rounds: 12, round: 180, rest: 60)
        let s = IntervalSummary.from(plan: plan, elapsed: plan.totalDuration)
        XCTAssertEqual(s.protocolName, "Boxing")
        XCTAssertEqual(s.rounds, 12)
        XCTAssertEqual(s.workSeconds, 180)
        XCTAssertEqual(s.restSeconds, 60)
        XCTAssertEqual(s.warmupSeconds, 0)
        XCTAssertEqual(s.cooldownSeconds, 0)
    }

    func testEndedEarlyCountsOnlyCompletedRounds() {
        // Tabata: 300 warm-up, then round 1 work [300,320], rest [320,330],
        // round 2 work [330,350]… End at 325 → only round 1's work is complete.
        let plan = IntervalPlan.tabata()
        let s = IntervalSummary.from(plan: plan, elapsed: 325)
        XCTAssertEqual(s.rounds, 8)
        XCTAssertEqual(s.completedRounds, 1, "stopped mid round-2 → 1 finished")
    }

    func testNoCompletedRoundsDuringWarmup() {
        let plan = IntervalPlan.tabata()
        let s = IntervalSummary.from(plan: plan, elapsed: 100) // still warming up
        XCTAssertEqual(s.completedRounds, 0)
    }

    func testRoundTripThroughJSON() {
        let s = IntervalSummary(protocolName: "Norwegian 4×4", rounds: 4,
                                workSeconds: 240, restSeconds: 180,
                                warmupSeconds: 600, cooldownSeconds: 300,
                                completedRounds: 3)
        let cardio = CardioWorkout(type: .hiit)
        cardio.intervalSummary = s
        XCTAssertFalse(cardio.intervalDetailData.isEmpty, "JSON should be stored")
        XCTAssertEqual(cardio.intervalSummary, s, "round-trips through the stored JSON")
    }
}
