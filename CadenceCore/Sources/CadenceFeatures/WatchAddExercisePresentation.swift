import Foundation
import CadenceCore

/// Presentation-only policy for the Watch Add Exercise picker and preview.
public enum WatchAddExercisePresentation {
    public enum RowAction: Equatable, Sendable {
        /// Opens the exercise info/preview screen; the only add is on the preview.
        case openPreview
        case addImmediately
    }

    public enum DetailPlacement: Equatable, Sendable {
        case belowActions
        case aboveActions
    }

    public enum BackTreatment: Equatable, Sendable {
        case leadingChevronOnly
        case labeledButton
    }

    public static let muscleGroupSectionTitle = "Muscle groups"
    public static var visibleMuscleGroups: [MuscleGroup] { MuscleGroup.canonicalOrder }
    public static let offersMoreMuscles = false
    public static let offersRecentExercises = false

    public static let exerciseNameMaxLines = 2
    public static let usesMarqueeForNames = false
    public static let minimumTouchHeight: Double = 44

    public static let rowAction: RowAction = .openPreview
    public static let rowAccessibilityHint = "View exercise details before adding."
    public static let detailPlacement: DetailPlacement = .belowActions
    public static let backTreatment: BackTreatment = .leadingChevronOnly
    public static let backAccessibilityLabel = "Back to exercises"

    /// Names are shown verbatim; wrapping/truncation is left to the system.
    public static func rowTitle(for name: String) -> String { name }

    public static func rowAccessibilityLabel(for name: String) -> String { name }

    public static func detailToggleTitle(isExpanded: Bool) -> String {
        isExpanded ? "Hide detail" : "Show detail"
    }
}
