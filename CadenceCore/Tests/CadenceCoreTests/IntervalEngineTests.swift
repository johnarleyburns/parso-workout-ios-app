import XCTest
@testable import CadenceCore

/// Field-testing §06 — interval plan expansion, phase location, and the
/// full-screen color state.
final class IntervalEngineTests: XCTestCase {

    func testTabataExpansion() {
        let plan = IntervalPlan.tabata(warmup: 300, rounds: 8, work: 20, rest: 10, cooldown: 300)
        // warmup + 8×(work+rest) + cooldown = 1 + 16 + 1 = 18 phases.
        XCTAssertEqual(plan.phases.count, 18)
        let tabataTotal: TimeInterval = 300 + 8 * 30 + 300
        XCTAssertEqual(plan.totalDuration, tabataTotal, accuracy: 0.001)
        XCTAssertEqual(plan.phases.first?.kind, .warmup)
        XCTAssertEqual(plan.phases.last?.kind, .cooldown)
        XCTAssertEqual(plan.phases.filter { $0.kind == .work }.count, 8)
    }

    func testNorwegian4x4Expansion() {
        let plan = IntervalPlan.norwegian4x4()
        XCTAssertEqual(plan.phases.filter { $0.kind == .work }.count, 4)
        // warmup 600 + 4×240 + 3×180 recover + 300 cooldown.
        let nwTotal: TimeInterval = 600 + 4 * 240 + 3 * 180 + 300
        XCTAssertEqual(plan.totalDuration, nwTotal, accuracy: 0.001)
        XCTAssertEqual(plan.phases.first(where: { $0.kind == .work })?.duration, 240)
    }

    func testBoxingExpansion() {
        let plan = IntervalPlan.boxing(rounds: 12, round: 180, rest: 60)
        XCTAssertEqual(plan.phases.filter { $0.kind == .work }.count, 12)
        XCTAssertEqual(plan.phases.filter { $0.kind == .rest }.count, 11) // no trailing rest
        let boxTotal: TimeInterval = 12 * 180 + 11 * 60
        XCTAssertEqual(plan.totalDuration, boxTotal, accuracy: 0.001)
    }

    func testPhaseLocationByElapsed() {
        let plan = IntervalPlan.boxing(rounds: 2, round: 180, rest: 60) // [work,rest,work]
        // 10s in → round 1 work, 170s left.
        let a = plan.state(atElapsed: 10)
        XCTAssertEqual(a?.phase.kind, .work)
        XCTAssertEqual(a?.phaseRemaining ?? 0, 170, accuracy: 0.001)
        // 200s in → rest (180..240), 40s left.
        XCTAssertEqual(plan.state(atElapsed: 200)?.phase.kind, .rest)
        // 250s in → round 2 work.
        XCTAssertEqual(plan.state(atElapsed: 250)?.phase.kind, .work)
        // past the end → complete.
        XCTAssertNil(plan.state(atElapsed: 999))
        XCTAssertTrue(plan.isComplete(atElapsed: 999))
    }

    func testGibalaExpansion() {
        let plan = IntervalPlan.gibala(warmup: 180, rounds: 8, work: 60, rest: 60, cooldown: 120)
        XCTAssertEqual(plan.name, "Gibala")
        XCTAssertEqual(plan.phases.filter { $0.kind == .work }.count, 8)
        XCTAssertEqual(plan.phases.filter { $0.kind == .rest }.count, 7)   // between rounds only
    }

    func testSITExpansion() {
        let plan = IntervalPlan.sit()
        XCTAssertEqual(plan.phases.filter { $0.kind == .work }.count, 4)
        XCTAssertEqual(plan.phases.first(where: { $0.kind == .work })?.duration, 30)
        XCTAssertTrue(plan.phases.contains { $0.kind == .rest && $0.duration == 240 })
    }

    func testREHITExpansion() {
        let plan = IntervalPlan.rehit()
        XCTAssertEqual(plan.phases.filter { $0.kind == .work }.count, 2)
        XCTAssertEqual(plan.phases.filter { $0.kind == .rest }.count, 1)   // one recovery between
        XCTAssertEqual(plan.phases.first?.kind, .warmup)
        XCTAssertEqual(plan.phases.last?.kind, .cooldown)
    }

    func testTenTwentyThirtyExpansion() {
        let plan = IntervalPlan.tenTwentyThirty(sets: 3, reps: 5)
        // 3 sets × 5 reps × (moderate + sprint) work phases = 30 work phases.
        XCTAssertEqual(plan.phases.filter { $0.kind == .work }.count, 30)
        XCTAssertTrue(plan.phases.contains { $0.label == "Sprint!" && $0.duration == 10 })
        XCTAssertTrue(plan.phases.contains { $0.label.hasPrefix("Recover") })
    }

    // MARK: Skip (feedback batch 5)

    func testElapsedAtNextPhaseFromWarmup() {
        // Gibala: warmup 180 → work 60 → rest 60 → …
        let plan = IntervalPlan.gibala(warmup: 180, rounds: 8, work: 60, rest: 60, cooldown: 120)
        // Anywhere inside the warm-up jumps to the end of the warm-up (180).
        XCTAssertEqual(plan.elapsedAtNextPhase(after: 0), 180, accuracy: 0.001)
        XCTAssertEqual(plan.elapsedAtNextPhase(after: 45), 180, accuracy: 0.001)
        XCTAssertEqual(plan.elapsedAtNextPhase(after: 179), 180, accuracy: 0.001)
    }

    func testElapsedAtNextPhaseMidRound() {
        let plan = IntervalPlan.gibala(warmup: 180, rounds: 8, work: 60, rest: 60, cooldown: 120)
        // 200s in → inside the first work phase (180..240) → next boundary 240.
        XCTAssertEqual(plan.elapsedAtNextPhase(after: 200), 240, accuracy: 0.001)
        // 250s in → inside the first rest phase (240..300) → next boundary 300.
        XCTAssertEqual(plan.elapsedAtNextPhase(after: 250), 300, accuracy: 0.001)
    }

    func testElapsedAtNextPhaseAtBoundary() {
        let plan = IntervalPlan.gibala(warmup: 180, rounds: 8, work: 60, rest: 60, cooldown: 120)
        // Exactly at a phase boundary skips the phase that *starts* there.
        XCTAssertEqual(plan.elapsedAtNextPhase(after: 180), 240, accuracy: 0.001)
    }

    func testElapsedAtNextPhaseOnLastPhaseEndsWorkout() {
        let plan = IntervalPlan.gibala(warmup: 180, rounds: 8, work: 60, rest: 60, cooldown: 120)
        // Inside the final cool-down → totalDuration (skip ends the workout).
        let total = plan.totalDuration
        XCTAssertEqual(plan.elapsedAtNextPhase(after: total - 30), total, accuracy: 0.001)
        // Past the end clamps to totalDuration too.
        XCTAssertEqual(plan.elapsedAtNextPhase(after: total + 100), total, accuracy: 0.001)
    }

    func testColorStateThresholds() {
        XCTAssertEqual(IntervalSignal.colorState(phase: .work, remaining: 60), .work)     // green
        XCTAssertEqual(IntervalSignal.colorState(phase: .work, remaining: 30), .warning)  // yellow
        XCTAssertEqual(IntervalSignal.colorState(phase: .work, remaining: 3), .imminent)  // flashing
        XCTAssertEqual(IntervalSignal.colorState(phase: .work, remaining: 1), .imminent)
        XCTAssertEqual(IntervalSignal.colorState(phase: .rest, remaining: 5), .rest)      // red
        XCTAssertEqual(IntervalSignal.colorState(phase: .warmup, remaining: 5), .neutral)
        XCTAssertEqual(IntervalSignal.colorState(phase: .cooldown, remaining: 5), .neutral)
    }
}
