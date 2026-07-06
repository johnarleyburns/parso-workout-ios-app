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
    /// Accumulated extra time added to the current phase (user taps "+1 min").
    private(set) var phaseExtension: TimeInterval = 0

    init(plan: IntervalPlan) {
        self.plan = plan
        self.clock = WorkoutClock(startedAt: Date())
    }

    var elapsed: TimeInterval { clock.elapsed(now: now) + skipped }
    var isComplete: Bool { clock.isEnded || elapsed >= plan.totalDuration + phaseExtension }
    var isPaused: Bool { clock.isPaused }

    private var current: (index: Int, phase: IntervalPhase, phaseRemaining: TimeInterval, overallRemaining: TimeInterval)? {
        plan.state(atElapsed: elapsed)
    }

    var currentPhaseID: Int? { current?.phase.id }
    var phaseKind: IntervalPhaseKind? { current?.phase.kind }
    var phaseLabel: String { current?.phase.label ?? (isComplete ? "Done" : "") }
    var phaseRemaining: TimeInterval { (current?.phaseRemaining ?? 0) + phaseExtension }
    var overallRemaining: TimeInterval { (current?.overallRemaining ?? 0) + phaseExtension }

    var colorState: FullScreenColorState {
        guard let c = current else { return .neutral }
        return IntervalSignal.colorState(phase: c.phase.kind, remaining: c.phaseRemaining)
    }

    func pause() { clock.pause(now: Date()) }
    func resume() { clock.resume(now: Date()) }
    func end() { clock.end(now: Date()) }

    /// Skips the active phase: jumps elapsed forward to the next phase boundary
    /// (feedback batch 5). Skipping the last phase pushes past `totalDuration`, so
    /// `isComplete` flips true and the view finishes.
    func skipPhase() {
        let target = plan.elapsedAtNextPhase(after: elapsed)
        skipped += max(0, target - elapsed)
    }

    /// Restarts the clock from now and clears any skip offset — used when the
    /// pre-workout HR gate is passed so elapsed starts at 0 (feedback batch 5).
    func restart() {
        clock = WorkoutClock(startedAt: Date())
        skipped = 0
        phaseExtension = 0
    }

    /// Adds extra time to the current phase (e.g. +1 min to warm-up or cool-down).
    func addTime(_ seconds: TimeInterval) {
        guard !isComplete else { return }
        phaseExtension += max(0, seconds)
    }
}
