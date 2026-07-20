import XCTest
@testable import CadenceFeatures
import CadenceCore

final class WatchCardioModelsTests: XCTestCase {

    // MARK: - WorkoutConfigurationSpec

    func testSpecForRun() {
        let spec = WorkoutConfigurationSpec(for: "run")
        XCTAssertEqual(spec.kind, .run)
        XCTAssertEqual(spec.location, .outdoor)
    }

    func testSpecForWalk() {
        let spec = WorkoutConfigurationSpec(for: "walk")
        XCTAssertEqual(spec.kind, .walk)
    }

    func testSpecForCycle() {
        let spec = WorkoutConfigurationSpec(for: "cycle")
        XCTAssertEqual(spec.kind, .cycle)
    }

    func testSpecForSwim_default25m() {
        let spec = WorkoutConfigurationSpec(for: "swim")
        XCTAssertEqual(spec.kind, .swim)
        if case .pool(let lapLength) = spec.location {
            XCTAssertEqual(lapLength, 25)
        } else { XCTFail("Expected pool location") }
    }

    func testSpecForHIIT() {
        let spec = WorkoutConfigurationSpec(for: "hiit")
        XCTAssertEqual(spec.kind, .hiit)
    }

    func testSpecForBoxing() {
        let spec = WorkoutConfigurationSpec(for: "boxing")
        XCTAssertEqual(spec.kind, .boxing)
    }

    func testSpecForRowing() {
        let spec = WorkoutConfigurationSpec(for: "rowing")
        XCTAssertEqual(spec.kind, .rowing)
    }

    func testSpecForOther() {
        let spec = WorkoutConfigurationSpec(for: "other")
        XCTAssertEqual(spec.kind, .other)
    }

    func testSpecForUnknown() {
        let spec = WorkoutConfigurationSpec(for: "garbage")
        XCTAssertEqual(spec.kind, .strength)
    }

    func testSpecCustomPool() {
        let spec = WorkoutConfigurationSpec(kind: .swim, location: .pool(lapLength: 50))
        if case .pool(let lapLength) = spec.location {
            XCTAssertEqual(lapLength, 50)
        } else { XCTFail("Expected pool") }
    }

    func testSpecCustomOutdoorRun() {
        let spec = WorkoutConfigurationSpec(kind: .run, location: .outdoor)
        XCTAssertEqual(spec.location, .outdoor)
    }

    // MARK: - CardioMetricsModel

    func testDistanceFormat_metric() {
        let m = CardioMetricsModel(kind: .run, unit: .kilograms)
        m.updateDistance(0)
        XCTAssertTrue(m.formatDistance().contains("m"))
    }

    func testDistanceFormat_miles() {
        let m = CardioMetricsModel(kind: .run, unit: .pounds)
        m.updateDistance(1609.344)
        XCTAssertTrue(m.formatDistance().contains("mi"))
    }

    func testPaceDivByZero_safe() {
        let m = CardioMetricsModel(kind: .run, unit: .kilograms)
        m.updateDistance(0)
        m.updateElapsed(0)
        XCTAssertEqual(m.formatPace(), "--")
    }

    func testHRZone() {
        let m = CardioMetricsModel(kind: .run, unit: .kilograms)
        m.updateHR(150)
        XCTAssertGreaterThan(m.hrZone, 0)
        XCTAssertLessThanOrEqual(m.hrZone, 5)
    }

    func testSplitPer500m() {
        let m = CardioMetricsModel(kind: .rowing, unit: .kilograms)
        m.updateDistance(1000)
        m.elapsed = 150
        m.recomputeSplitPer500m()
        XCTAssertEqual(m.splitPer500m ?? 0, 75, accuracy: 1)
    }

    func testAutoPaused() {
        let m = CardioMetricsModel(kind: .run, unit: .kilograms)
        XCTAssertFalse(m.isAutoPaused)
        m.setAutoPaused(true)
        XCTAssertTrue(m.isAutoPaused)
        m.resetAutoPause()
        XCTAssertFalse(m.isAutoPaused)
    }

    func testLapCount_defaultsToZero() {
        let m = CardioMetricsModel(kind: .run, unit: .kilograms)
        XCTAssertEqual(m.lapCount, 0)
        XCTAssertEqual(m.manualLapCount, 0)
    }

    func testLapCount_totalIncludesManual() {
        let m = CardioMetricsModel(kind: .run, unit: .kilograms)
        m.lapCount = 3
        m.manualLapCount = 2
        XCTAssertEqual(m.lapCount + m.manualLapCount, 5)
    }

    func testDistanceFormat_imperial_roundsCorrectly() {
        let m = CardioMetricsModel(kind: .run, unit: .pounds)
        m.updateDistance(0)
        XCTAssertTrue(m.formatDistance().contains("mi"))
    }

    func testSplitPer500m_zeroDistance() {
        let m = CardioMetricsModel(kind: .rowing, unit: .kilograms)
        m.updateDistance(0)
        m.elapsed = 100
        m.recomputeSplitPer500m()
        XCTAssertNil(m.splitPer500m)
    }

    // MARK: - AutoPauseDetector

    func testHighSpeed_noPause() {
        var d = AutoPauseDetector()
        XCTAssertEqual(d.evaluate(speedMPS: 3.0, isDisabled: false), .none)
    }

    func testLowSpeed_withoutDebounce_noPause() {
        var d = AutoPauseDetector()
        XCTAssertEqual(d.evaluate(speedMPS: 0.3, isDisabled: false), .none)
    }

    func testLowSpeed_withDebounce_pauses() {
        var d = AutoPauseDetector(speedThreshold: 0.5, debounceSeconds: 0.0)
        XCTAssertEqual(d.evaluate(speedMPS: 0.3, isDisabled: false), .pause)
    }

    func testResumeAfterPause() {
        var d = AutoPauseDetector(speedThreshold: 0.5, debounceSeconds: 0.0)
        _ = d.evaluate(speedMPS: 0.3, isDisabled: false)
        d.reset()
        XCTAssertEqual(d.evaluate(speedMPS: 3.0, isDisabled: false), .none)
    }

    func testDisabled_noPause() {
        var d = AutoPauseDetector(speedThreshold: 0.5, debounceSeconds: 0.0)
        XCTAssertEqual(d.evaluate(speedMPS: 0.1, isDisabled: true), .none)
    }

    func testNilSpeed_noPause() {
        var d = AutoPauseDetector()
        XCTAssertEqual(d.evaluate(speedMPS: nil, isDisabled: false), .none)
    }

    // MARK: - IntervalSetupModel

    func testHIITDefaults() {
        let m = IntervalSetupModel(kind: "HIIT")
        XCTAssertEqual(m.rounds, 8)
        XCTAssertEqual(m.warmupSeconds, 180)
        XCTAssertEqual(m.workSeconds, 30)
        XCTAssertEqual(m.restSeconds, 30)
        XCTAssertEqual(m.cooldownSeconds, 120)
    }

    func testBoxingDefaults() {
        let m = IntervalSetupModel(kind: "Boxing")
        XCTAssertEqual(m.rounds, 8)
        XCTAssertEqual(m.warmupSeconds, 180)
        XCTAssertEqual(m.workSeconds, 300)
        XCTAssertEqual(m.restSeconds, 60)
        XCTAssertEqual(m.cooldownSeconds, 120)
    }

    func testIntervalAcceptsSyncedWarmupAndCooldown() {
        let m = IntervalSetupModel(kind: "Boxing", warmupSeconds: 240, cooldownSeconds: 60)
        XCTAssertEqual(m.warmupSeconds, 240)
        XCTAssertEqual(m.cooldownSeconds, 60)
    }

    func testIntervalInitializerClampsSyncedWarmupAndCooldown() {
        let m = IntervalSetupModel(kind: "Boxing", warmupSeconds: 900, cooldownSeconds: -20)
        XCTAssertEqual(m.warmupSeconds, 600)
        XCTAssertEqual(m.cooldownSeconds, 0)
    }

    func testIntervalClamp() {
        let m = IntervalSetupModel(kind: "HIIT")
        m.rounds = 100
        m.warmupSeconds = -10
        m.workSeconds = 1000
        m.restSeconds = 0
        m.cooldownSeconds = 1000
        let c = m.clamped()
        XCTAssertEqual(c.rounds, 30)
        XCTAssertEqual(c.warmupSeconds, 0)
        XCTAssertEqual(c.workSeconds, 600)
        XCTAssertEqual(c.restSeconds, 5)
        XCTAssertEqual(c.cooldownSeconds, 600)
    }

    func testWarmupAndCooldownAllowZeroButWorkAndRestDoNot() {
        let m = IntervalSetupModel(kind: "Boxing")
        m.warmupSeconds = 0
        m.workSeconds = 0
        m.restSeconds = 0
        m.cooldownSeconds = 0
        let c = m.clamped()
        XCTAssertEqual(c.warmupSeconds, 0)
        XCTAssertEqual(c.workSeconds, 5)
        XCTAssertEqual(c.restSeconds, 5)
        XCTAssertEqual(c.cooldownSeconds, 0)
    }

    func testIntervalPlanBuilt() {
        let m = IntervalSetupModel(kind: "Custom")
        let plan = m.intervalPlan()
        XCTAssertEqual(plan.name, "Custom")
        XCTAssertEqual(plan.workRounds, 8)
    }

    func testIntervalPlanWorkRoundsMatchesRounds() {
        let m = IntervalSetupModel(kind: "HIIT")
        m.rounds = 3
        let plan = m.intervalPlan()
        XCTAssertEqual(plan.workRounds, 3)
    }

    func testIntervalPlanUsesConfiguredWarmupAndCooldown() {
        let m = IntervalSetupModel(kind: "Boxing", warmupSeconds: 240, cooldownSeconds: 60)
        m.rounds = 2
        let plan = m.intervalPlan()
        XCTAssertEqual(plan.phases.first?.kind, .warmup)
        XCTAssertEqual(plan.phases.first?.duration, 240)
        XCTAssertEqual(plan.phases.last?.kind, .cooldown)
        XCTAssertEqual(plan.phases.last?.duration, 60)
    }

    func testIntervalPlanOmitsZeroWarmupAndCooldown() {
        let m = IntervalSetupModel(kind: "Boxing")
        m.rounds = 1
        m.warmupSeconds = 0
        m.cooldownSeconds = 0
        let plan = m.intervalPlan()
        XCTAssertFalse(plan.phases.contains { $0.kind == .warmup })
        XCTAssertFalse(plan.phases.contains { $0.kind == .cooldown })
        XCTAssertEqual(plan.workRounds, 1)
    }
}
