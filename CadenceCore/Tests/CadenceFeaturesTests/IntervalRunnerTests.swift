import Foundation
import Testing
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures

/// Moved from Cadence/CadenceTests/IntervalRunnerTests.swift (test-pyramid Phase 2),
/// converted from swift-testing to XCTest to match CadenceCoreTests. Now runs
/// headlessly under `swift test` instead of the simulator.
struct IntervalRunnerTests {

    private func tabataPlan() -> IntervalPlan {
        IntervalPlan.tabata(warmup: 300, rounds: 4, work: 20, rest: 10, cooldown: 300)
    }

    private func runner(for plan: IntervalPlan, elapsed time: TimeInterval) -> IntervalRunner {
        let r = IntervalRunner(plan: plan)
        r.restart()
        r.now = r.clock.startedAt.addingTimeInterval(time)
        return r
    }

    @Test func phaseRemainingWithoutExtension() {
        let plan = tabataPlan()
        let r = runner(for: plan, elapsed: 60)
        #expect(r.phaseKind == .warmup)
        #expect(r.phaseRemaining == 240)
        #expect(r.overallRemaining == plan.totalDuration - 60)
        #expect(!r.isComplete)
    }

    @Test func workPhaseWithoutExtension() {
        let r = runner(for: tabataPlan(), elapsed: 310)
        #expect(r.phaseKind == .work)
        #expect(r.phaseRemaining == 10)
    }

    @Test func isCompleteAfterTotalDuration() {
        let plan = tabataPlan()
        let r = runner(for: plan, elapsed: plan.totalDuration)
        #expect(r.isComplete)
    }

    @Test func warmupExtensionDelaysPhaseChange() {
        let r = runner(for: tabataPlan(), elapsed: 290)
        r.addTime(60)
        #expect(r.phaseKind == .warmup)
        #expect(r.phaseRemaining == 70)
    }

    @Test func warmupExtensionKeepsUserInWarmupPastOriginalBoundary() {
        let r = runner(for: tabataPlan(), elapsed: 310)
        #expect(r.phaseKind == .work)
        #expect(!r.isComplete)
    }

    @Test func warmupExtensionStillInWarmupAtOriginalBoundary() {
        let r = runner(for: tabataPlan(), elapsed: 290)
        r.addTime(60)
        r.now = r.clock.startedAt.addingTimeInterval(305)
        #expect(r.phaseKind == .warmup)
        #expect(r.phaseRemaining == 55)
    }

    @Test func warmupExtensionTransitionsAfterExtensionConsumed() {
        let r = runner(for: tabataPlan(), elapsed: 290)
        r.addTime(60)
        r.now = r.clock.startedAt.addingTimeInterval(365)
        #expect(r.phaseKind == .work)
    }

    @Test func cooldownExtensionPreventsCompletion() {
        let r = runner(for: tabataPlan(), elapsed: 710)
        r.addTime(60)
        #expect(r.phaseKind == .cooldown)
        #expect(!r.isComplete)
        #expect(r.phaseRemaining == 70)
    }

    @Test func cooldownExtensionCompletesAfterExtendedBoundary() {
        let r = runner(for: tabataPlan(), elapsed: 710)
        r.addTime(60)
        r.now = r.clock.startedAt.addingTimeInterval(785)
        #expect(r.isComplete)
    }

    @Test func doubleExtensionAddsCorrectly() {
        let r = runner(for: tabataPlan(), elapsed: 290)
        r.addTime(60)
        r.addTime(60)
        #expect(r.phaseKind == .warmup)
        #expect(r.phaseRemaining == 130)
    }

    @Test func skipDuringExtendedWarmupAdvancesToWork() {
        let r = runner(for: tabataPlan(), elapsed: 290)
        r.addTime(60)
        r.skipPhase()
        #expect(r.phaseKind == .work)
        #expect(r.phaseRemaining == 20)
    }

    @Test func skipWithNoExtensionInWarmup() {
        let r = runner(for: tabataPlan(), elapsed: 60)
        r.skipPhase()
        #expect(r.phaseKind == .work)
        #expect(r.phaseRemaining == 20)
    }

    @Test func overallRemainingReflectsExtension() {
        let plan = tabataPlan()
        let r = runner(for: plan, elapsed: 290)
        r.addTime(60)
        #expect(r.overallRemaining == plan.totalDuration - 290 + 60)
    }

    @Test func extensionAppliedToCorrectPhaseAtBoundary() {
        let r = runner(for: tabataPlan(), elapsed: 300)
        #expect(r.phaseKind == .work)
        r.addTime(60)
        #expect(r.phaseKind == .work)
        #expect(r.phaseRemaining == 80)
    }

    @Test func addTimeIgnoredWhenComplete() {
        let plan = tabataPlan()
        let r = runner(for: plan, elapsed: plan.totalDuration + 10)
        #expect(r.isComplete)
        r.addTime(60)
        #expect(r.isComplete)
    }

    @Test func restartClearsExtensions() {
        let r = runner(for: tabataPlan(), elapsed: 290)
        r.addTime(60)
        #expect(r.phaseRemaining == 70)
        r.restart()
        r.now = r.clock.startedAt
        #expect(r.phaseKind == .warmup)
        #expect(r.phaseRemaining == 300)
    }

    @Test func extensionFromMidWarmupCountsDownCorrectly() {
        let r = runner(for: tabataPlan(), elapsed: 150)
        r.addTime(60)
        #expect(r.phaseKind == .warmup)
        #expect(r.phaseRemaining == 210)
        r.now = r.clock.startedAt.addingTimeInterval(160)
        #expect(r.phaseKind == .warmup)
        #expect(r.phaseRemaining == 200)
    }
}
