import Foundation
import CadenceCore

/// Save/load seam for the Summary "Edit cardio minutes" editor. Existing values
/// are read from the stored summary in one step (never a placeholder 0), and a
/// save persists first, posts `workoutHistoryChanged` only after success, and
/// rolls the in-memory edit back on failure so the UI stays honest.
@MainActor
public enum ManualCardioMinutesSaver {
    public struct Minutes: Equatable, Sendable {
        public let moderate: Int
        public let vigorous: Int
    }

    /// `nil` when the summary has not loaded yet; callers show a loading state
    /// instead of seeding the steppers with zero.
    public static func existingMinutes(from summary: CardioMinuteSummary?) -> Minutes? {
        guard let summary else { return nil }
        return Minutes(moderate: Int((summary.moderateDuration / 60).rounded()),
                       vigorous: Int((summary.vigorousDuration / 60).rounded()))
    }

    @discardableResult
    public static func save(session: WorkoutSession, moderate: Int, vigorous: Int,
                            persist: () throws -> Void,
                            center: NotificationCenter = .default) -> Result<Void, Error> {
        let previousSummary = session.intensitySummary
        let previousFlag = session.hasManualCardioMinutesOverride
        let previousUpdatedAt = session.updatedAt
        session.setManualCardioMinutes(moderate: moderate, vigorous: vigorous)
        do {
            try persist()
        } catch {
            session.intensitySummary = previousSummary
            session.hasManualCardioMinutesOverride = previousFlag
            session.updatedAt = previousUpdatedAt
            return .failure(error)
        }
        center.post(name: .workoutHistoryChanged, object: nil)
        return .success(())
    }
}
