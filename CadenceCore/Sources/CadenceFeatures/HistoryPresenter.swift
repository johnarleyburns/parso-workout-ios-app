import Foundation
import CadenceCore

/// Builds the unified, soft-delete-aware, date-sorted history feed the History
/// screen renders. Moved out of `HistoryView` (test-pyramid Phase 1) so the
/// exclusion + ordering rules are unit-tested headlessly instead of via XCUITest.
public enum HistoryPresenter {

    /// Merges strength sessions and cardio workouts into a single feed, filtered
    /// by soft-delete state and sorted newest-first.
    ///
    /// - Parameter showDeleted: `false` → only live workouts; `true` → only the
    ///   soft-deleted ones (the "View Deleted" mode).
    public static func entries(sessions: [WorkoutSession],
                               cardio: [CardioWorkout],
                               showDeleted: Bool = false) -> [WorkoutHistoryEntry] {
        let s = sessions
            .filter { showDeleted ? $0.deletedAt != nil : $0.deletedAt == nil }
            .map(WorkoutHistoryEntry.strength)
        let c = cardio
            .filter { showDeleted ? $0.deletedAt != nil : $0.deletedAt == nil }
            .map(WorkoutHistoryEntry.cardio)
        return (s + c).sorted { $0.date > $1.date }
    }
}
