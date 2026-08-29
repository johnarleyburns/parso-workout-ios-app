import Foundation
import CadenceCore
import CadenceFeatures

/// What to launch once the countdown finishes.
struct PendingWorkout: Identifiable {
    let id = UUID()
    enum Kind { case strength, plan(WorkoutPlan, [Int]?), reuse(WorkoutSession), outdoor(CardioType), interval(IntervalLaunch), timer(CardioType)
        var isStrength: Bool {
            switch self {
            case .strength, .plan, .reuse: true
            case .outdoor, .interval, .timer: false
            }
        }
        var cardioType: CardioType? {
            switch self {
            case .outdoor(let c), .timer(let c): return c
            case .interval(let l): return l.saveType
            case .strength, .plan, .reuse: return nil
            }
        }
    }
    let kind: Kind
}

enum WorkoutStartCue {
    case countdown, single, none
}

/// Pushed destinations reachable from Home.
enum HomeRoute: Hashable {
    case settings, coach, coachPreferences
    case history
    case yourPlan
    case workoutEditor(EditablePlan)
    case customExercises
    case runAssessment(AssessmentKind)
}
