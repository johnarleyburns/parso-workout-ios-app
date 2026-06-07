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

    init(plan: IntervalPlan) {
        self.plan = plan
        self.clock = WorkoutClock(startedAt: Date())
    }

    var elapsed: TimeInterval { clock.elapsed(now: now) }
    var isComplete: Bool { clock.isEnded || plan.isComplete(atElapsed: elapsed) }
    var isPaused: Bool { clock.isPaused }

    private var current: (index: Int, phase: IntervalPhase, phaseRemaining: TimeInterval, overallRemaining: TimeInterval)? {
        plan.state(atElapsed: elapsed)
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
}
