import Foundation

/// What choosing an exercise (near match, custom creation) does in each
/// presentation of the exercise browser. Modal pickers complete and dismiss;
/// the Find browser opens the exercise's detail and never dismisses.
public enum ExerciseSelectionPolicy {
    public enum Outcome: Equatable, Sendable {
        case completeAndDismiss
        case openDetail
        case addToDraftAndStay
    }

    /// Planning (Find) adds to the draft and stays put; modal pickers complete.
    public static func outcome(isPlanning: Bool) -> Outcome {
        isPlanning ? .addToDraftAndStay : .completeAndDismiss
    }

    public static func outcome(isBrowse: Bool) -> Outcome {
        isBrowse ? .openDetail : .completeAndDismiss
    }

    public static func showsCancel(isBrowse: Bool) -> Bool { !isBrowse }

    public static func nearMatchTitle(isBrowse: Bool) -> String {
        isBrowse ? "View exercise" : "Use this exercise"
    }
}

/// Find-local draft summary bar content, prepared outside the view.
public struct PlanningDraftSummary: Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let exerciseCount: Int

    public init(id: UUID, title: String, exerciseCount: Int) {
        self.id = id; self.title = title; self.exerciseCount = exerciseCount
    }

    public static let emptyMessage = "No workout draft yet. Add exercises to start one."

    public static func headline(_ summary: PlanningDraftSummary?) -> String {
        guard let summary, summary.exerciseCount > 0 else { return emptyMessage }
        return summary.title
    }

    public static func countText(_ count: Int) -> String {
        count == 1 ? "1 exercise" : "\(count) exercises"
    }
}
