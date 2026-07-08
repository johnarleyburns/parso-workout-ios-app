import Testing
import Foundation
@testable import Cadence
import CadenceCore

struct IntervalRunnerTests {

    private func tabataPlan() -> IntervalPlan {
        IntervalPlan.tabata(warmup: 300, rounds: 4, work: 20, rest: 10, cooldown: 300)
    }

    private func runner(for plan: IntervalPlan, elapsed time: TimeInterval) -> IntervalRunner {
        let r = IntervalRunner(plan: plan)
        r.restart()
        // Simulate elapsed time by advancing `now`.
        r.now = r.clock.startedAt.addingTimeInterval(time)
        return r
    }

    // MARK: No-extension baseline — phase walk matches plan

    @Test func phaseRemainingWithoutExtension() {
        let plan = tabataPlan()
        let r = runner(for: plan, elapsed: 60)
        #expect(r.phaseKind == .warmup)
        #expect(r.phaseRemaining == 240)
        #expect(r.overallRemaining == plan.totalDuration - 60)
        #expect(!r.isComplete)
    }

    @Test func workPhaseWithoutExtension() {
        let plan = tabataPlan()
        // warmup=300, so 310 is 10s into first work phase
        let r = runner(for: plan, elapsed: 310)
        #expect(r.phaseKind == .work)
        #expect(r.phaseRemaining == 10)
    }

    @Test func isCompleteAfterTotalDuration() {
        let plan = tabataPlan()
        let r = runner(for: plan, elapsed: plan.totalDuration)
        #expect(r.isComplete)
    }

    // MARK: Warm-up extension

    @Test func warmupExtensionDelaysPhaseChange() {
        let plan = tabataPlan()
        let r = runner(for: plan, elapsed: 290) // 10s left
        r.addTime(60)
        // 10s original + 60s extension = 70s remaining
        #expect(r.phaseKind == .warmup)
        #expect(r.phaseRemaining == 70, "expected 70s remaining (10 from plan + 60 extension)")
    }

    @Test func warmupExtensionKeepsUserInWarmupPastOriginalBoundary() {
        let plan = tabataPlan()
        let r = runner(for: plan, elapsed: 310) // past original warmup boundary (300)
        #expect(r.phaseKind == .work, "without extension, 310s is work phase")
        #expect(!r.isComplete)
    }

    @Test func warmupExtensionStillInWarmupAtOriginalBoundary() {
        let plan = tabataPlan()
        let r = runner(for: plan, elapsed: 290) // 10s left in warmup
        r.addTime(60)
        // Advance to 305 — normally in work phase, but extension should keep in warmup
        r.now = r.clock.startedAt.addingTimeInterval(305)
        #expect(r.phaseKind == .warmup, "305s should still be warmup due to 60s extension")
        #expect(r.phaseRemaining == 55, "expected 55s remaining (300+60-305)")
    }

    @Test func warmupExtensionTransitionsAfterExtensionConsumed() {
        let plan = tabataPlan()
        let r = runner(for: plan, elapsed: 290) // 10s left
        r.addTime(60) // total warmup = 360s
        // Advance past the extended boundary
        r.now = r.clock.startedAt.addingTimeInterval(365)
        #expect(r.phaseKind == .work, "should transition to work after extended warmup ends")
    }

    // MARK: Cooldown extension

    @Test func cooldownExtensionPreventsCompletion() {
        let plan = tabataPlan()
        // Enter cooldown: warmup=300 + 4×(20+10)=120 + cooldown=300, total=720
        // Cooldown starts at 420, ends at 720
        let r = runner(for: plan, elapsed: 710) // 10s left in cooldown
        r.addTime(60) // extend cooldown by 60s
        #expect(r.phaseKind == .cooldown)
        #expect(!r.isComplete)
        #expect(r.phaseRemaining == 70, "expected 70s remaining (10 from plan + 60 extension)")
    }

    @Test func cooldownExtensionCompletesAfterExtendedBoundary() {
        let plan = tabataPlan()
        let r = runner(for: plan, elapsed: 710)
        r.addTime(60)
        // Advance past extended total (720 + 60 = 780)
        r.now = r.clock.startedAt.addingTimeInterval(785)
        #expect(r.isComplete)
    }

    // MARK: Double extension

    @Test func doubleExtensionAddsCorrectly() {
        let plan = tabataPlan()
        let r = runner(for: plan, elapsed: 290) // 10s left
        r.addTime(60)
        r.addTime(60)
        #expect(r.phaseKind == .warmup)
        #expect(r.phaseRemaining == 130, "expected 130s (10 original + 120 from two extensions)")
    }

    // MARK: Skip during extension

    @Test func skipDuringExtendedWarmupAdvancesToWork() {
        let plan = tabataPlan()
        let r = runner(for: plan, elapsed: 290) // 10s left
        r.addTime(60)
        r.skipPhase()
        #expect(r.phaseKind == .work)
        // Extensions should be cleared after skip
        #expect(r.phaseRemaining == 20, "expected 20s (first work phase)")
    }

    @Test func skipWithNoExtensionInWarmup() {
        let plan = tabataPlan()
        let r = runner(for: plan, elapsed: 60)
        r.skipPhase()
        #expect(r.phaseKind == .work)
        #expect(r.phaseRemaining == 20, "expected 20s (first work phase)")
    }

    // MARK: Overall remaining with extensions

    @Test func overallRemainingReflectsExtension() {
        let plan = tabataPlan()
        let r = runner(for: plan, elapsed: 290) // 10s left
        r.addTime(60)
        #expect(r.overallRemaining == plan.totalDuration - 290 + 60)
    }

    @Test func extensionAppliedToCorrectPhaseAtBoundary() {
        let plan = tabataPlan()
        let r = runner(for: plan, elapsed: 300) // exactly at warmup boundary → work phase
        #expect(r.phaseKind == .work, "at exactly 300s we are in the first work phase")
        r.addTime(60) // extends work phase (index 1), not warmup (index 0)
        #expect(r.phaseKind == .work)
        #expect(r.phaseRemaining == 80, "expected 80s (20 original work + 60 extension)")
    }

    // MARK: addTime guards

    @Test func addTimeIgnoredWhenComplete() {
        let plan = tabataPlan()
        let r = runner(for: plan, elapsed: plan.totalDuration + 10)
        #expect(r.isComplete)
        r.addTime(60) // should be a no-op
        #expect(r.isComplete)
    }

    @Test func restartClearsExtensions() {
        let plan = tabataPlan()
        let r = runner(for: plan, elapsed: 290)
        r.addTime(60)
        #expect(r.phaseRemaining == 70)
        r.restart()
        r.now = r.clock.startedAt // align `now` with the new clock
        #expect(r.phaseKind == .warmup)
        #expect(r.phaseRemaining == 300) // original warmup restored
    }

    // MARK: Warmup-extension phase boundary edge where original boundary = warmup duration

    @Test func extensionFromMidWarmupCountsDownCorrectly() {
        let plan = tabataPlan()
        let r = runner(for: plan, elapsed: 150) // halfway (150/300)
        r.addTime(60)
        #expect(r.phaseKind == .warmup)
        #expect(r.phaseRemaining == 210, "expected 210s remaining (150 original + 60 extension)")
        // Advance 10s
        r.now = r.clock.startedAt.addingTimeInterval(160)
        #expect(r.phaseKind == .warmup)
        #expect(r.phaseRemaining == 200, "expected 200s remaining")
    }
}
