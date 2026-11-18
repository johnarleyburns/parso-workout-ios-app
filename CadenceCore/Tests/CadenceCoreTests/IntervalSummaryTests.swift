import Testing
@testable import CadenceCore

/// Interval history detail (feedback batch 4 / roadmap P5): deriving a
/// persistable `IntervalSummary` from a live plan, including ended-early rounds.
struct IntervalSummaryTests {

    @Test func tabataStructure() {
        let plan = IntervalPlan.tabata() // 5:00 warm-up, 8×(20/10), 5:00 cool-down
        let s = IntervalSummary.from(plan: plan, elapsed: plan.totalDuration)
        #expect(s.protocolName == "Tabata")
        #expect(s.rounds == 8)
        #expect(s.workSeconds == 20)
        #expect(s.restSeconds == 10)
        #expect(s.warmupSeconds == 300)
        #expect(s.cooldownSeconds == 300)
        #expect(s.completedRounds == 8, "a full run completes every round")
    }

    @Test func boxingHasNoWarmupOrCooldown() {
        let plan = IntervalPlan.boxing(rounds: 12, round: 180, rest: 60)
        let s = IntervalSummary.from(plan: plan, elapsed: plan.totalDuration)
        #expect(s.protocolName == "Boxing")
        #expect(s.rounds == 12)
        #expect(s.workSeconds == 180)
        #expect(s.restSeconds == 60)
        #expect(s.warmupSeconds == 0)
        #expect(s.cooldownSeconds == 0)
    }

    @Test func endedEarlyCountsOnlyCompletedRounds() {
        // Tabata: 300 warm-up, then round 1 work [300,320], rest [320,330],
        // round 2 work [330,350]… End at 325 → only round 1's work is complete.
        let plan = IntervalPlan.tabata()
        let s = IntervalSummary.from(plan: plan, elapsed: 325)
        #expect(s.rounds == 8)
        #expect(s.completedRounds == 1, "stopped mid round-2 → 1 finished")
    }

    @Test func noCompletedRoundsDuringWarmup() {
        let plan = IntervalPlan.tabata()
        let s = IntervalSummary.from(plan: plan, elapsed: 100) // still warming up
        #expect(s.completedRounds == 0)
    }

    @Test func cooldownSkippedEarlyRecordsActualTime() {
        // Tabata cool-down is the last phase (5:00). Skipping it at 3:00 should
        // record 3:00, not the planned 5:00 (feedback batch 6).
        let plan = IntervalPlan.tabata()
        let cooldownStart = plan.totalDuration - 300
        let s = IntervalSummary.from(plan: plan, elapsed: cooldownStart + 180)
        #expect(s.warmupSeconds == 300, "warm-up was fully completed earlier")
        #expect(s.cooldownSeconds == 180, "only 3:00 of the planned 5:00 cool-down")
        #expect(s.completedRounds == 8, "all work rounds finished before cool-down")
    }

    @Test func warmupSkippedEarlyRecordsActualTime() {
        let plan = IntervalPlan.tabata()
        let s = IntervalSummary.from(plan: plan, elapsed: 120) // 2:00 into the 5:00 warm-up
        #expect(s.warmupSeconds == 120, "actual warm-up time consumed")
        #expect(s.cooldownSeconds == 0)
        #expect(s.completedRounds == 0)
    }

    @Test func roundTripThroughJSON() {
        let s = IntervalSummary(protocolName: "Norwegian 4×4", rounds: 4,
                                workSeconds: 240, restSeconds: 180,
                                warmupSeconds: 600, cooldownSeconds: 300,
                                completedRounds: 3)
        let cardio = CardioWorkout(type: .hiit)
        cardio.intervalSummary = s
        #expect(!cardio.intervalDetailData.isEmpty, "JSON should be stored")
        #expect(cardio.intervalSummary == s, "round-trips through the stored JSON")
    }
}
