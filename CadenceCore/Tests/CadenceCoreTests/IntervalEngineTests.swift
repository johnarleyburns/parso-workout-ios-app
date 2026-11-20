import Foundation
import Testing
@testable import CadenceCore

/// Field-testing §06 — interval plan expansion, phase location, and the
/// full-screen color state.
struct IntervalEngineTests {

    @Test func tabataExpansion() {
        let plan = IntervalPlan.tabata(warmup: 300, rounds: 8, work: 20, rest: 10, cooldown: 300)
        // warmup + 8×(work+rest) + cooldown = 1 + 16 + 1 = 18 phases.
        #expect(plan.phases.count == 18)
        let tabataTotal: TimeInterval = 300 + 8 * 30 + 300
        #expect(abs(plan.totalDuration - tabataTotal) <= 0.001)
        #expect(plan.phases.first?.kind == .warmup)
        #expect(plan.phases.last?.kind == .cooldown)
        #expect(plan.phases.filter { $0.kind == .work }.count == 8)
    }

    @Test func norwegian4x4Expansion() {
        let plan = IntervalPlan.norwegian4x4()
        #expect(plan.phases.filter { $0.kind == .work }.count == 4)
        // warmup 600 + 4×240 + 3×180 recover + 300 cooldown.
        // Keep the arithmetic in explicit Double terms: the mixed literal
        // expression is slow enough for the Linux Swift 6.1 type checker to
        // reject it as "unable to type-check in reasonable time".
        let nwTotal: TimeInterval = 600.0 + (4.0 * 240.0) + (3.0 * 180.0) + 300.0
        #expect(abs(plan.totalDuration - nwTotal) <= 0.001)
        #expect(plan.phases.first(where: { $0.kind == .work })?.duration == 240)
    }

    @Test func boxingExpansion() {
        let plan = IntervalPlan.boxing(rounds: 12, round: 180, rest: 60)
        #expect(plan.phases.filter { $0.kind == .work }.count == 12)
        #expect(plan.phases.filter { $0.kind == .rest }.count == 11) // no trailing rest
        let boxTotal: TimeInterval = 12 * 180 + 11 * 60
        #expect(abs(plan.totalDuration - boxTotal) <= 0.001)
    }

    @Test func phaseLocationByElapsed() {
        let plan = IntervalPlan.boxing(rounds: 2, round: 180, rest: 60) // [work,rest,work]
        // 10s in → round 1 work, 170s left.
        let a = plan.state(atElapsed: 10)
        #expect(a?.phase.kind == .work)
        #expect(abs((a?.phaseRemaining ?? 0) - 170) <= 0.001)
        // 200s in → rest (180..240), 40s left.
        #expect(plan.state(atElapsed: 200)?.phase.kind == .rest)
        // 250s in → round 2 work.
        #expect(plan.state(atElapsed: 250)?.phase.kind == .work)
        // past the end → complete.
        #expect(plan.state(atElapsed: 999) == nil)
        #expect(plan.isComplete(atElapsed: 999))
    }

    @Test func gibalaExpansion() {
        let plan = IntervalPlan.gibala(warmup: 180, rounds: 8, work: 60, rest: 60, cooldown: 120)
        #expect(plan.name == "Gibala")
        #expect(plan.phases.filter { $0.kind == .work }.count == 8)
        #expect(plan.phases.filter { $0.kind == .rest }.count == 7)   // between rounds only
    }

    @Test func sITExpansion() {
        let plan = IntervalPlan.sit()
        #expect(plan.phases.filter { $0.kind == .work }.count == 4)
        #expect(plan.phases.first(where: { $0.kind == .work })?.duration == 30)
        #expect(plan.phases.contains { $0.kind == .rest && $0.duration == 240 })
    }

    @Test func rEHITExpansion() {
        let plan = IntervalPlan.rehit()
        #expect(plan.phases.filter { $0.kind == .work }.count == 2)
        #expect(plan.phases.filter { $0.kind == .rest }.count == 1)   // one recovery between
        #expect(plan.phases.first?.kind == .warmup)
        #expect(plan.phases.last?.kind == .cooldown)
    }

    @Test func gillenExpansion() {
        let plan = IntervalPlan.gillen()
        #expect(plan.name == "Gillen")
        #expect(plan.phases.filter { $0.kind == .work }.count == 3)
        #expect(plan.phases.filter { $0.kind == .work }.allSatisfy { $0.duration == 20 })
        let rests = plan.phases.filter { $0.kind == .rest }
        #expect(rests.count == 2)
        #expect(rests.allSatisfy { $0.duration == 120 })
        #expect(plan.phases.first?.kind == .warmup)
        #expect(plan.phases.first?.duration == 120)
        #expect(plan.phases.last?.kind == .cooldown)
        #expect(plan.phases.last?.duration == 180)
        #expect(plan.totalDuration == 600)
        #expect(IntervalPlan.rehit().totalDuration == 460)
    }

    @Test func tenTwentyThirtyExpansion() {
        let plan = IntervalPlan.tenTwentyThirty(sets: 3, reps: 5)
        // 3 sets × 5 reps × (moderate + sprint) work phases = 30 work phases.
        #expect(plan.phases.filter { $0.kind == .work }.count == 30)
        #expect(plan.phases.contains { $0.label == "Sprint!" && $0.duration == 10 })
        #expect(plan.phases.contains { $0.label.hasPrefix("Recover") })
    }

    // MARK: Skip (feedback batch 5)

    @Test func elapsedAtNextPhaseFromWarmup() {
        // Gibala: warmup 180 → work 60 → rest 60 → …
        let plan = IntervalPlan.gibala(warmup: 180, rounds: 8, work: 60, rest: 60, cooldown: 120)
        // Anywhere inside the warm-up jumps to the end of the warm-up (180).
        #expect(abs(plan.elapsedAtNextPhase(after: 0) - 180) <= 0.001)
        #expect(abs(plan.elapsedAtNextPhase(after: 45) - 180) <= 0.001)
        #expect(abs(plan.elapsedAtNextPhase(after: 179) - 180) <= 0.001)
    }

    @Test func elapsedAtNextPhaseMidRound() {
        let plan = IntervalPlan.gibala(warmup: 180, rounds: 8, work: 60, rest: 60, cooldown: 120)
        // 200s in → inside the first work phase (180..240) → next boundary 240.
        #expect(abs(plan.elapsedAtNextPhase(after: 200) - 240) <= 0.001)
        // 250s in → inside the first rest phase (240..300) → next boundary 300.
        #expect(abs(plan.elapsedAtNextPhase(after: 250) - 300) <= 0.001)
    }

    @Test func elapsedAtNextPhaseAtBoundary() {
        let plan = IntervalPlan.gibala(warmup: 180, rounds: 8, work: 60, rest: 60, cooldown: 120)
        // Exactly at a phase boundary skips the phase that *starts* there.
        #expect(abs(plan.elapsedAtNextPhase(after: 180) - 240) <= 0.001)
    }

    @Test func elapsedAtNextPhaseOnLastPhaseEndsWorkout() {
        let plan = IntervalPlan.gibala(warmup: 180, rounds: 8, work: 60, rest: 60, cooldown: 120)
        // Inside the final cool-down → totalDuration (skip ends the workout).
        let total = plan.totalDuration
        #expect(abs(plan.elapsedAtNextPhase(after: total - 30) - total) <= 0.001)
        // Past the end clamps to totalDuration too.
        #expect(abs(plan.elapsedAtNextPhase(after: total + 100) - total) <= 0.001)
    }

    @Test func colorStateThresholds() {
        #expect(IntervalSignal.colorState(phase: .work, remaining: 60, phaseDuration: 180) == .work)
        #expect(IntervalSignal.colorState(phase: .work, remaining: 30, phaseDuration: 180) == .warning)
        #expect(IntervalSignal.colorState(phase: .work, remaining: 3, phaseDuration: 180) == .imminent)
        #expect(IntervalSignal.colorState(phase: .work, remaining: 1, phaseDuration: 180) == .imminent)
        #expect(IntervalSignal.colorState(phase: .rest, remaining: 5, phaseDuration: 180) == .rest)
        #expect(IntervalSignal.colorState(phase: .warmup, remaining: 5, phaseDuration: 180) == .neutral)
        #expect(IntervalSignal.colorState(phase: .cooldown, remaining: 5, phaseDuration: 180) == .neutral)
    }
}
