import Foundation

/// Where a Strength plan came from. Only the manual Find draft is durable.
public enum StrengthPlanOrigin: Equatable, Sendable {
    case manualFindDraft
    case muscleCoverageSuggestion
    case personalizedSuggestion
    case library
    case scheduled
}

public enum StrengthPlanPersistence: Equatable, Sendable {
    case durablePlanningDraft
    case transientEditor
}

public enum StrengthPlanPolicy {
    public static func persistence(for origin: StrengthPlanOrigin) -> StrengthPlanPersistence {
        origin == .manualFindDraft ? .durablePlanningDraft : .transientEditor
    }
}

/// Strength tab's final "Draft workout" section (entry point only).
public enum StrengthDraftSectionPresenter {
    public enum State: Equatable, Sendable {
        case empty
        case summary(title: String, exerciseCount: Int)
    }

    public static let sectionIdentifier = "weights.draftWorkout"
    public static let emptyIdentifier = "weights.draftWorkout.empty"
    public static let continueIdentifier = "weights.draftWorkout.continue"
    public static let emptyMessage = "Add exercises from Find to begin a draft workout."

    public static func state(for summary: PlanningDraftSummary?) -> State {
        guard let summary, summary.exerciseCount > 0 else { return .empty }
        return .summary(title: summary.title, exerciseCount: summary.exerciseCount)
    }
}

public enum StrengthScreenLayout {
    public enum Section: Equatable, Sendable {
        case suggest, muscleCoverage, quickStart, previousWorkouts, library, hrMonitoring, draftWorkout
    }
    public static let sections: [Section] = [
        .suggest, .muscleCoverage, .quickStart, .previousWorkouts, .library, .hrMonitoring, .draftWorkout]
}

/// The manual draft has no cross-tab entry: no root strip, no root sheet.
public enum RootDraftPresentationPolicy {
    public static let showsGlobalDraftStrip = false
    public static let showsGlobalDraftSheet = false
}

public enum MuscleCoverageSuggestionLayout {
    public enum Section: Equatable, Sendable { case suggestedExercises }
    public static let title = "Strength Workout"
    public static let sections: [Section] = [.suggestedExercises]
}

public enum TransientStrengthEditorContent {
    public enum Item: Equatable, Sendable {
        case startWorkout, sendToWatch, scheduleThisWorkout
        case exerciseRows, addExercise, suggestExercise
        case trainingPartners, volumeSummary
    }
    public static let order: [Item] = [
        .startWorkout, .sendToWatch, .scheduleThisWorkout,
        .exerciseRows, .addExercise, .suggestExercise,
        .trainingPartners, .volumeSummary]
}
