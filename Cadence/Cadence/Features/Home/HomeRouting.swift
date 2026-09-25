import Foundation
import SwiftUI
import SwiftData
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

/// Resolves history routes in the destination's own SwiftData query. Home's
/// compact My Workouts rows are prepared asynchronously, and resolving a tap
/// against that parent snapshot could briefly produce the generic unavailable
/// surface even though the tapped record was present in the store.
struct HomeHistoryDestinationView: View {
    let route: HistorySummaryRoute
    @Binding var path: NavigationPath

    @Query(sort: \WorkoutSession.date, order: .reverse)
    private var sessions: [WorkoutSession]
    @Query(sort: \CardioWorkout.start, order: .reverse)
    private var cardio: [CardioWorkout]

    var body: some View {
        switch route {
        case .strength(let id):
            if let session = sessions.first(where: { $0.id == id }) {
                WorkoutSummaryView(
                    data: .from(session: session),
                    onEdit: { path.append(HistorySummaryRoute.strengthFocused(id, nil)) })
            } else {
                MissingWorkoutRouteView()
            }
        case .strengthFocused(let id, let exerciseID):
            if let session = sessions.first(where: { $0.id == id }) {
                SessionView(session: session, initiallyExpandedExerciseID: exerciseID)
            } else {
                MissingWorkoutRouteView()
            }
        case .cardio(let id):
            if let workout = cardio.first(where: { $0.id == id }) {
                CardioDetailView(workout: workout)
            } else {
                MissingWorkoutRouteView()
            }
        }
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
