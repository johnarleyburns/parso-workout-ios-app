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
    case more
    case settings, coach, coachPreferences
    case history, plannedWorkouts
    case workoutEditor(EditablePlan)
    case customExercises
    case runAssessment(AssessmentKind)
}

/// Secondary destinations stay reachable without competing with the primary
/// start/review loop on Today.
struct MoreView: View {
    var body: some View {
        List {
            Section("Review") {
                NavigationLink(value: HomeRoute.history) {
                    Label("Workout History", systemImage: "clock.arrow.circlepath")
                }
                NavigationLink(value: HomeRoute.plannedWorkouts) {
                    Label("Planned Workouts", systemImage: "calendar")
                }
                NavigationLink { TestsView() } label: {
                    Label("Tests", systemImage: "checkmark.seal")
                }
                .accessibilityIdentifier("more.tests")
            }

            Section("Customize") {
                NavigationLink(value: HomeRoute.customExercises) {
                    Label("Exercises", systemImage: "figure.strengthtraining.traditional")
                }
                NavigationLink(value: HomeRoute.coachPreferences) {
                    Label("Coach Preferences", systemImage: "slider.horizontal.3")
                }
                NavigationLink(value: HomeRoute.coach) {
                    Label("Coach Insights", systemImage: "lightbulb")
                }
            }

            Section("Learn") {
                NavigationLink { CoachMethodologyView() } label: {
                    Label("Coach Methodology", systemImage: "book.pages")
                }
                NavigationLink { CoachResearchUpdatesView() } label: {
                    Label("Coach Research Updates", systemImage: "newspaper")
                }
                NavigationLink { CoachAboutView() } label: {
                    Label("About the Coach", systemImage: "info.circle")
                }
            }

            Section("App") {
                NavigationLink(value: HomeRoute.settings) {
                    Label("Settings", systemImage: "gearshape")
                }
                .accessibilityIdentifier("more.settings")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("More")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("home.more")
    }
}
