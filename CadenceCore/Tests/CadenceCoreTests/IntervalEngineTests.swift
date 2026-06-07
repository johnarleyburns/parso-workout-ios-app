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
