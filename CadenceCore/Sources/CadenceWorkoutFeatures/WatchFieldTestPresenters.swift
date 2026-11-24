import CadenceCore
import Foundation

/// Pure decisions behind the Watch field-testing batch. Keeping these out of
/// the SwiftUI views makes the requested behavior headlessly testable.
public enum WatchSuggestedStrengthRefreshPolicy {
    /// Build once on first appearance. A SwiftUI body update must not blank an
    /// already visible Lift preview; only a genuinely newer phone mirror does.
    public static func shouldGenerate(lastRevision: String?, currentRevision: String?,
                                      hasLaunch: Bool) -> Bool {
        guard hasLaunch else { return true }
        return lastRevision != currentRevision
    }
}

public struct WatchLiftWhyExercise: Equatable, Sendable, Identifiable {
    public let exerciseName: String
    public let whyExercise: String
    public let whySetRep: String

    public var id: String { exerciseName }

    public init(exerciseName: String, whyExercise: String, whySetRep: String) {
        self.exerciseName = exerciseName
        self.whyExercise = whyExercise
        self.whySetRep = whySetRep
    }
}

/// Read-only presentation of the shared coach rationale for the Watch Lift
/// preview. No reasoning is recomputed on the Watch.
public struct WatchLiftWhyPresentation: Equatable, Sendable {
    public static let title = "Why this workout"
    public var title: String { Self.title }

    public let whyWorkout: String
    public let exercises: [WatchLiftWhyExercise]

    public init?(rationale: SuggestedWorkoutRationale?) {
        guard let rationale else { return nil }
        self.whyWorkout = rationale.whyWorkout
        self.exercises = rationale.exercises.map {
            WatchLiftWhyExercise(exerciseName: $0.exerciseName,
                                 whyExercise: $0.whyExercise,
                                 whySetRep: $0.whySetRep)
        }
    }
}

/// Defense in depth for the suggestion UI: even if a generator ever returns a
/// movement that is already in the workout, the Watch never presents it as a
/// new suggestion.
public enum WatchExerciseSuggestionGuard {
    public static func isAlreadyInWorkout(_ name: String, activeNames: [String]) -> Bool {
        let key = ExerciseSuggestionExclusionKey.forName(name)
        let dedup = ExerciseLibrary.dedupKey(name)
        return activeNames.contains {
            ExerciseSuggestionExclusionKey.forName($0) == key
                || ExerciseLibrary.dedupKey($0) == dedup
        }
    }
}

public enum WatchAddExerciseSuggestionPresentation {
    public static let pageTitle = "Add Exercise"
    public static let sectionTitle = "Suggested"
    public static let customRowTitle = "Add Custom"
    public static let rowAccessibilityHint = "Add exercise"
    public static let rowIdentifierPrefix = "watchAddExercise.suggested."
}

/// "Z1"…"Z5" for the live HR badge, using the same shared zone bands as every
/// other cardio surface. nil when there is no sample or no usable max HR.
public enum WatchHeartRateZoneText {
    public static func code(bpm: Double?, maxHR: Double) -> String? {
        guard let bpm, bpm > 0, maxHR > 0 else { return nil }
        return "Z\(CardioMath.hrZone(bpm: bpm, maxHR: maxHR))"
    }
}

public enum WatchPhasePresentation {
    public static let warmUpTitle = "Warm-up"
    public static let coolDownTitle = "Cool Down"
    public static let endSystemImage = "xmark"
}

/// Sets and cardio values shown as the two rings on the active-workout Summary
/// page. Progress is clamped and division-safe so an empty session is stable.
public struct WatchLiveSummaryPresentation: Equatable, Sendable {
    public let setsCompleted: Int
    public let setsPlanned: Int
    public let cardioMinutes: Int
    public let setsProgress: Double
    public let cardioProgress: Double

    public static func make(setsCompleted: Int, setsPlanned: Int,
                            cardioMinutes: Double,
                            cardioTargetMinutes: Double = 30) -> Self {
        let completed = max(0, setsCompleted)
        let planned = max(0, setsPlanned)
        let setTarget = max(planned, completed, 1)
        let minutes = max(0, cardioMinutes)
        let cardioTarget = max(cardioTargetMinutes, 1)
        return Self(
            setsCompleted: completed,
            setsPlanned: planned,
            cardioMinutes: Int(minutes.rounded()),
            setsProgress: min(1, Double(completed) / Double(setTarget)),
            cardioProgress: min(1, minutes / cardioTarget))
    }
}

public enum WatchWarmUpControlPresentation {
    public static let skipSystemImage = "chevron.forward.2"
    public static let addOneMinuteLabel = "+1"

    public static func pauseSystemImage(isPaused: Bool) -> String {
        isPaused ? "play.fill" : "pause.fill"
    }
}

public enum WatchSetEntryPresentation {
    /// The Log action is a green checkbox with no surrounding button box.
    public static let logButtonSystemImage = "checkmark.square.fill"
    public static let repsUnit = "rps"
    /// Tight spacing between the small header rows.
    public static let headerSpacing: Double = 4
    /// Extra breathing room below the header and above the weight/reps row;
    /// the row itself sits tighter to the space below it.
    public static let fieldTopSpacing: Double = 10
}

public enum WatchStrengthControlsPresentation {
    public static let title = "Workout"
    /// Only a small margin when the pause explanation is actually present.
    public static let pauseReasonTopPadding: Double = 2
    public static let finishConfirmationTitle = "End Workout?"
    public static let finishCoolDownTitle = "Cool Down"
    public static let finishCancelTitle = "Cancel"
}

public enum WatchPartnerDirectory {
    /// Names the user has trained with before that are not already in this
    /// workout's rotation. Case/whitespace variants count as the same person.
    public static func addable(allNames: [String], currentNames: [String]) -> [String] {
        var taken = Set(currentNames.map(key))
        var result: [String] = []
        for raw in allNames {
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let nameKey = key(name)
            guard taken.insert(nameKey).inserted else { continue }
            result.append(name)
        }
        return result
    }

    private static func key(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
