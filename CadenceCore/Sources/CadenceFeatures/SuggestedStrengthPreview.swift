import Foundation
import CadenceCore

/// User-facing actions of the Strength "Suggest a Workout" preview sheet plus
/// the asynchronous/schedule outcomes that feed back into it.
public enum SuggestedStrengthAction: Equatable, Sendable {
    case start
    case schedule
    case suggestAnother
    case cancel
    case interactiveDismiss
    case replacementSucceeded(EditablePlan, token: UUID)
    case replacementUnavailable(token: UUID)
    case scheduleSucceeded
    case scheduleCancelled
}

/// Side effects the view must perform after a reduction.
public enum SuggestedStrengthEffect: Equatable, Sendable {
    case none
    /// Dismiss the sheet exactly once, then hand the plan to the launch path.
    case dismissThenStart(EditablePlan)
    case dismissAfterSchedule
    /// Regenerate for this interaction only; never persisted.
    case requestAlternative(excluding: Set<String>, token: UUID)
    /// Dismiss and cancel any in-flight generation. Mutates nothing.
    case cancelPresentation
}

/// Stable accessibility identifiers and ordered titles for the four actions.
public enum SuggestedStrengthActionContract {
    public struct Entry: Equatable, Sendable {
        public let action: SuggestedStrengthAction
        public let title: String
        public let accessibilityIdentifier: String
    }

    public static let startIdentifier = "suggestedStrength.start"
    public static let scheduleIdentifier = "suggestedStrength.schedule"
    public static let anotherIdentifier = "suggestedStrength.another"
    public static let cancelIdentifier = "suggestedStrength.cancel"

    public static let startTitle = "Start this Workout"
    public static let scheduleTitle = "Schedule this Workout"
    public static let anotherTitle = "Suggest another"
    public static let cancelTitle = "Cancel"

    /// Exactly the order the user sees; Cancel is last and text-only.
    public static let ordered: [Entry] = [
        Entry(action: .start, title: startTitle, accessibilityIdentifier: startIdentifier),
        Entry(action: .schedule, title: scheduleTitle, accessibilityIdentifier: scheduleIdentifier),
        Entry(action: .suggestAnother, title: anotherTitle, accessibilityIdentifier: anotherIdentifier),
        Entry(action: .cancel, title: cancelTitle, accessibilityIdentifier: cancelIdentifier),
    ]
}

/// Presentation policy: only the suggested-strength wrapper owns preview
/// Cancel / Suggest another semantics. Every other editor flow is unchanged.
public enum WorkoutPlanEditorPresentation: Equatable, Sendable {
    case manual, library, previousWorkout, scheduled, suggestedStrength

    public var showsSuggestedPreviewActions: Bool { self == .suggestedStrength }
}

public struct SuggestedStrengthPreviewState: Equatable, Sendable {
    public var plan: EditablePlan?
    /// The plan as last edited by the user, handed over on Start/Schedule.
    public var editedPlan: EditablePlan?
    public var isRegenerating = false
    public var isSchedulePresented = false
    public var unavailableMessage: String?
    public private(set) var activeToken: UUID?
    private var hasStarted = false

    public init(plan: EditablePlan?) {
        self.plan = plan
        self.editedPlan = plan
    }

    public var isPresented: Bool { plan != nil }

    /// Exercise identities (exclusion keys) of the displayed suggestion.
    public var displayedExerciseKeys: Set<String> {
        Set((editedPlan ?? plan)?.exercises.map { ExerciseSuggestionExclusionKey.forName($0.name) } ?? [])
    }

    public mutating func reduce(_ action: SuggestedStrengthAction,
                                newToken: @autoclosure () -> UUID = UUID()) -> SuggestedStrengthEffect {
        guard plan != nil else {
            // Nothing presented: late results and repeats are ignored.
            return .none
        }
        switch action {
        case .start:
            guard !hasStarted, !isRegenerating, let current = editedPlan ?? plan else { return .none }
            hasStarted = true
            clearPresentation()
            return .dismissThenStart(current)
        case .schedule:
            guard !isRegenerating else { return .none }
            isSchedulePresented = true
            return .none
        case .scheduleCancelled:
            isSchedulePresented = false
            return .none
        case .scheduleSucceeded:
            guard isSchedulePresented else { return .none }
            clearPresentation()
            return .dismissAfterSchedule
        case .suggestAnother:
            guard !isRegenerating else { return .none }
            let token = newToken()
            isRegenerating = true
            unavailableMessage = nil
            activeToken = token
            return .requestAlternative(excluding: displayedExerciseKeys, token: token)
        case .cancel, .interactiveDismiss:
            clearPresentation()
            return .cancelPresentation
        case let .replacementSucceeded(newPlan, token):
            guard isRegenerating, token == activeToken else { return .none }
            plan = newPlan
            editedPlan = newPlan
            finishRegeneration()
            return .none
        case let .replacementUnavailable(token):
            guard isRegenerating, token == activeToken else { return .none }
            finishRegeneration()
            unavailableMessage = SuggestedStrengthPreviewState.noAlternativeMessage
            return .none
        }
    }

    public static let noAlternativeMessage =
        "No different workout is available right now. Your current suggestion is unchanged; you can try again, edit it, or cancel."

    private mutating func finishRegeneration() {
        isRegenerating = false
        activeToken = nil
    }

    private mutating func clearPresentation() {
        plan = nil
        editedPlan = nil
        isRegenerating = false
        isSchedulePresented = false
        activeToken = nil
    }
}

public enum SuggestedStrengthAlternative {
    /// Value-only request for one alternative. The exclusion applies to this
    /// request alone; stored exclusion preferences are never touched.
    public static func request(from base: CoachSuggestionRequest,
                               excludingKeys keys: Set<String>) -> CoachSuggestionRequest {
        let ids = Set(base.input.candidates
            .filter { keys.contains($0.id) || keys.contains(ExerciseSuggestionExclusionKey.forName($0.name)) }
            .map(\.id))
        return CoachSuggestionRequest(
            input: base.input.excluding(candidateIDs: ids), unit: base.unit,
            warmupMinutes: base.warmupMinutes, cooldownMinutes: base.cooldownMinutes,
            failureMessage: base.failureMessage)
    }
}
