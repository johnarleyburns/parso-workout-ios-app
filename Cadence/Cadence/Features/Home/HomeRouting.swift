import Foundation
import SwiftUI
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

struct CombinedSessionLaunch: Identifiable {
    let id: UUID
    let session: Session
    let lease: LiveWorkoutLease

    init(session: Session, lease: LiveWorkoutLease) {
        self.id = session.id
        self.session = session
        self.lease = lease
    }
}

enum WorkoutStartCue {
    case countdown, single, none
}

/// Pushed destinations reachable from Home.
enum HomeRoute: Hashable {
    case settings, coach, coachPreferences, savedWorkouts
    case history, plannedWorkouts
    case workoutEditor(EditablePlan)
    case customExercises
    case runAssessment(AssessmentKind)
}

/// History destinations carry stable identifiers only. SwiftData models are
/// resolved at the destination boundary, never stored in NavigationPath.
enum HistorySummaryRoute: Hashable {
    case strength(UUID)
    case strengthFocused(UUID, UUID?)
    case cardio(UUID)
}

struct MissingWorkoutRouteView: View {
    var body: some View {
        ContentUnavailableView(
            "Workout unavailable",
            systemImage: "exclamationmark.triangle",
            description: Text("This workout is no longer available in local history. Return and try another workout."))
    }
}

/// Debug/UI-test-only route diagnostics. It intentionally contains no workout
/// contents or health data; it records only the route boundary and failure.
struct HomeRouteDiagnostics: Equatable, Sendable {
    let route: String
    let source: String
    let requestID: UUID
    let failureReason: String?
}

/// A route must fail visibly and recoverably. In particular, an older or
/// partially migrated scheduled payload must never leave SwiftUI on a blank
/// destination (the field-tested yellow warning page).
enum HomeRouteFailure: Identifiable {
    case scheduledWorkout(UUID)

    var id: String {
        switch self {
        case .scheduledWorkout(let id): "scheduled-workout-\(id.uuidString)"
        }
    }

    var title: String { "Couldn't open this workout" }

    var message: String {
        switch self {
        case .scheduledWorkout:
            "This scheduled workout could not be read. It is still saved, and you can try opening it again or edit it from Planned Workouts."
        }
    }
}
