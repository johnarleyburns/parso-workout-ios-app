import Foundation
import Observation
import CadenceCore

/// Drives an `IntervalPlan` against a wall-clock timer (field-testing §06), so
/// the protocol stays correct across backgrounding. The view sets `now` each
/// tick and reads the derived phase/colour; cues fire on phase change.
@Observable
final class IntervalRunner {
    let plan: IntervalPlan
    private(set) var clock: WorkoutClock
    var now = Date()
    /// Time skipped forward via `skipPhase()` (feedback batch 5) — added on top of
    /// the wall-clock elapsed so skipping a phase jumps to the next boundary.
    private(set) var skipped: TimeInterval = 0
    /// Per-phase extra time added by the user (e.g. "+1 min" to warm-up or
    /// cool-down). Keyed by the plan's phase index so extensions are scoped to
    /// the specific phase they were applied to and phase boundaries shift
    /// correctly.
    private var phaseExtensions: [Int: TimeInterval] = [:]

    init(plan: IntervalPlan) {
        self.plan = plan
        self.clock = WorkoutClock(startedAt: Date())
    }

    var elapsed: TimeInterval { clock.elapsed(now: now) + skipped }
    var isComplete: Bool { clock.isEnded || current == nil }
    var isPaused: Bool { clock.isPaused }

    /// The total duration of the plan including all per-phase extensions.
    private var effectiveTotalDuration: TimeInterval {
        plan.totalDuration + phaseExtensions.values.reduce(0, +)
    }

    /// Walks the plan's phases manually, applying per-phase extensions to each
    /// phase's effective duration so both the displayed remaining time and the
    /// phase-transition boundary reflect added time.
    private var current: (index: Int, phase: IntervalPhase, phaseRemaining: TimeInterval, overallRemaining: TimeInterval)? {
        guard elapsed >= 0, !plan.phases.isEmpty else { return nil }
        var acc: TimeInterval = 0
        for (i, p) in plan.phases.enumerated() {
            let ext = phaseExtensions[i] ?? 0
            let dur = p.duration + ext
            if elapsed < acc + dur {
                let phaseRemaining = (acc + dur) - elapsed
                return (i, p, phaseRemaining, effectiveTotalDuration - elapsed)
            }
            acc += dur
        }
        return nil
    }

    var currentPhaseID: Int? { current?.phase.id }
    var phaseKind: IntervalPhaseKind? { current?.phase.kind }
    var phaseLabel: String { current?.phase.label ?? (isComplete ? "Done" : "") }
    var phaseRemaining: TimeInterval { current?.phaseRemaining ?? 0 }
    var overallRemaining: TimeInterval { current?.overallRemaining ?? 0 }

    var colorState: FullScreenColorState {
        guard let c = current else { return .neutral }
        return IntervalSignal.colorState(phase: c.phase.kind, remaining: c.phaseRemaining)
    }

    func pause() { clock.pause(now: Date()) }
    func resume() { clock.resume(now: Date()) }
    func end() { clock.end(now: Date()) }

    /// Skips the active phase: jumps elapsed forward to the next phase boundary
    /// including any per-phase extensions so the skip respects added time.
    /// Skipping the last phase pushes past `effectiveTotalDuration`, so
    /// `isComplete` flips true and the view finishes.
    func skipPhase() {
        var acc: TimeInterval = 0
        for (i, p) in plan.phases.enumerated() {
            let ext = phaseExtensions[i] ?? 0
            acc += p.duration + ext
            if acc > elapsed + 0.0001 {
                skipped += acc - elapsed
                phaseExtensions.removeAll()
                return
            }
        }
        skipped += max(0, effectiveTotalDuration - elapsed)
        phaseExtensions.removeAll()
    }

    /// Restarts the clock from now and clears any skip offset — used when the
    /// pre-workout HR gate is passed so elapsed starts at 0 (feedback batch 5).
    func restart() {
        clock = WorkoutClock(startedAt: Date())
        skipped = 0
        phaseExtensions.removeAll()
    }

    /// Adds extra time to the current phase (e.g. +1 min to warm-up or cool-down).
    func addTime(_ seconds: TimeInterval) {
        guard !isComplete, let idx = current?.index else { return }
        phaseExtensions[idx, default: 0] += max(0, seconds)
    }
}
