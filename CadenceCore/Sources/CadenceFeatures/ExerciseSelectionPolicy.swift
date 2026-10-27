import Foundation

/// What choosing an exercise (near match, custom creation) does in each
/// presentation of the exercise browser. Modal pickers complete and dismiss;
/// the Find browser opens the exercise's detail and never dismisses.
public enum ExerciseSelectionPolicy {
    public enum Outcome: Equatable, Sendable {
        case completeAndDismiss
        case openDetail
    }

    public static func outcome(isBrowse: Bool) -> Outcome {
        isBrowse ? .openDetail : .completeAndDismiss
    }

    public static func showsCancel(isBrowse: Bool) -> Bool { !isBrowse }

    public static func nearMatchTitle(isBrowse: Bool) -> String {
        isBrowse ? "View exercise" : "Use this exercise"
    }
}
