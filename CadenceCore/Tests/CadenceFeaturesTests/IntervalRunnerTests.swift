import XCTest
import Foundation
import CadenceCore
import CadenceFeatures

/// Moved from Cadence/CadenceTests/IntervalRunnerTests.swift (test-pyramid Phase 2),
/// converted from swift-testing to XCTest to match CadenceCoreTests. Now runs
/// headlessly under `swift test` instead of the simulator.
final class IntervalRunnerTests: XCTestCase {

    private func tabataPlan() -> IntervalPlan {
        IntervalPlan.tabata(warmup: 300, rounds: 4, work: 20, rest: 10, cooldown: 300)
    }

    private func runner(for plan: IntervalPlan, elapsed time: TimeInterval) -> IntervalRunner {
        let r = IntervalRunner(plan: plan)
        r.restart()
        r.now = r.clock.startedAt.addingTimeInterval(time)
        return r
    }

    func testPhaseRemainingWithoutExtension() {
        let plan = tabataPlan()
        let r = runner(for: plan, elapsed: 60)
        XCTAssertEqual(r.phaseKind, .warmup)
        XCTAssertEqual(r.phaseRemaining, 240)
        XCTAssertEqual(r.overallRemaining, plan.totalDuration - 60)
        XCTAssertFalse(r.isComplete)
    }

    func testWorkPhaseWithoutExtension() {
        let r = runner(for: tabataPlan(), elapsed: 310)
        XCTAssertEqual(r.phaseKind, .work)
        XCTAssertEqual(r.phaseRemaining, 10)
    }

    func testIsCompleteAfterTotalDuration() {
        let plan = tabataPlan()
        let r = runner(for: plan, elapsed: plan.totalDuration)
        XCTAssertTrue(r.isComplete)
    }

    func testWarmupExtensionDelaysPhaseChange() {
        let r = runner(for: tabataPlan(), elapsed: 290)
        r.addTime(60)
        XCTAssertEqual(r.phaseKind, .warmup)
        XCTAssertEqual(r.phaseRemaining, 70)
    }

    func testWarmupExtensionKeepsUserInWarmupPastOriginalBoundary() {
        let r = runner(for: tabataPlan(), elapsed: 310)
        XCTAssertEqual(r.phaseKind, .work)
        XCTAssertFalse(r.isComplete)
    }

    func testWarmupExtensionStillInWarmupAtOriginalBoundary() {
        let r = runner(for: tabataPlan(), elapsed: 290)
        r.addTime(60)
        r.now = r.clock.startedAt.addingTimeInterval(305)
        XCTAssertEqual(r.phaseKind, .warmup)
        XCTAssertEqual(r.phaseRemaining, 55)
    }

    func testWarmupExtensionTransitionsAfterExtensionConsumed() {
        let r = runner(for: tabataPlan(), elapsed: 290)
        r.addTime(60)
        r.now = r.clock.startedAt.addingTimeInterval(365)
        XCTAssertEqual(r.phaseKind, .work)
    }

    func testCooldownExtensionPreventsCompletion() {
        let r = runner(for: tabataPlan(), elapsed: 710)
        r.addTime(60)
        XCTAssertEqual(r.phaseKind, .cooldown)
        XCTAssertFalse(r.isComplete)
        XCTAssertEqual(r.phaseRemaining, 70)
    }

    func testCooldownExtensionCompletesAfterExtendedBoundary() {
        let r = runner(for: tabataPlan(), elapsed: 710)
        r.addTime(60)
        r.now = r.clock.startedAt.addingTimeInterval(785)
        XCTAssertTrue(r.isComplete)
    }

    func testDoubleExtensionAddsCorrectly() {
        let r = runner(for: tabataPlan(), elapsed: 290)
        r.addTime(60)
        r.addTime(60)
        XCTAssertEqual(r.phaseKind, .warmup)
        XCTAssertEqual(r.phaseRemaining, 130)
    }

    func testSkipDuringExtendedWarmupAdvancesToWork() {
        let r = runner(for: tabataPlan(), elapsed: 290)
        r.addTime(60)
        r.skipPhase()
        XCTAssertEqual(r.phaseKind, .work)
        XCTAssertEqual(r.phaseRemaining, 20)
    }

    func testSkipWithNoExtensionInWarmup() {
        let r = runner(for: tabataPlan(), elapsed: 60)
        r.skipPhase()
        XCTAssertEqual(r.phaseKind, .work)
        XCTAssertEqual(r.phaseRemaining, 20)
    }

    func testOverallRemainingReflectsExtension() {
        let plan = tabataPlan()
        let r = runner(for: plan, elapsed: 290)
        r.addTime(60)
        XCTAssertEqual(r.overallRemaining, plan.totalDuration - 290 + 60)
    }

    func testExtensionAppliedToCorrectPhaseAtBoundary() {
        let r = runner(for: tabataPlan(), elapsed: 300)
        XCTAssertEqual(r.phaseKind, .work)
        r.addTime(60)
        XCTAssertEqual(r.phaseKind, .work)
        XCTAssertEqual(r.phaseRemaining, 80)
    }

    func testAddTimeIgnoredWhenComplete() {
        let plan = tabataPlan()
        let r = runner(for: plan, elapsed: plan.totalDuration + 10)
        XCTAssertTrue(r.isComplete)
        r.addTime(60)
        XCTAssertTrue(r.isComplete)
    }

    func testRestartClearsExtensions() {
        let r = runner(for: tabataPlan(), elapsed: 290)
        r.addTime(60)
        XCTAssertEqual(r.phaseRemaining, 70)
        r.restart()
        r.now = r.clock.startedAt
        XCTAssertEqual(r.phaseKind, .warmup)
        XCTAssertEqual(r.phaseRemaining, 300)
    }

    func testExtensionFromMidWarmupCountsDownCorrectly() {
        let r = runner(for: tabataPlan(), elapsed: 150)
        r.addTime(60)
        XCTAssertEqual(r.phaseKind, .warmup)
        XCTAssertEqual(r.phaseRemaining, 210)
        r.now = r.clock.startedAt.addingTimeInterval(160)
        XCTAssertEqual(r.phaseKind, .warmup)
        XCTAssertEqual(r.phaseRemaining, 200)
    }
}
