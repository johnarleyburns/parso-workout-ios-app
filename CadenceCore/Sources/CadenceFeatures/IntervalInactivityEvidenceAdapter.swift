import Foundation

/// Value-only mapping from a `CombinedPlanRunner` to `CardioActivityEvidence`.
///
/// A runner that is actively progressing through configured warm-up/work/rest/cooldown
/// is in a planned phase (phase progression is valid activity, so rest never triggers
/// inactivity). A runner that is not running (never started/stalled outside a phase),
/// paused without an origin, or otherwise abandoned can enter the automatic pause/end
/// policy. A user pause is passed as `.manual` and never auto-ends; a finished or
/// cancelled runner is never inactive. Timer ticks are never user activity.
public enum IntervalInactivityEvidenceAdapter {
    public static func evidence(
        runner: CombinedPlanRunner,
        lastUserActionAt: Date?,
        lastSensorEvidenceAt: Date?,
        pauseOrigin: CardioPauseOrigin?,
        autoPausedAt: Date?
    ) -> CardioActivityEvidence {
        CardioActivityEvidence(
            lastUserActionAt: lastUserActionAt,
            lastDistanceProgressAt: nil,
            lastMotionAt: nil,
            lastQualifyingHeartRateAt: lastSensorEvidenceAt,
            isInPlannedIntervalPhase: runner.state == .running || runner.isComplete,
            pauseOrigin: pauseOrigin,
            autoPausedAt: autoPausedAt)
    }
}
