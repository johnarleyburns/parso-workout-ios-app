import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

extension HomeView {
    @ViewBuilder
    func homeNavigationDestinations<Content: View>(_ content: Content) -> some View {
        content
            .navigationDestination(for: HistorySummaryRoute.self) { route in
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
            .navigationDestination(for: HomeRoute.self) { route in
                switch route {
                case .settings: SettingsView()
                case .history: HistoryView(path: pathBinding)
                case .plannedWorkouts: PlannedWorkoutsListView()
                case .savedWorkouts:
                    TemplatesView(onStart: { plan in
                        path = NavigationPath()
                        handleEditorStart(plan)
                    })
                case .coach:
                    CoachInsightsView(
                        insights: coachInsights,
                        onFixCustomExercises: { path.append(HomeRoute.customExercises) },
                        onInsightAction: { handleInsightAction($0) })
                case .coachPreferences: CoachSchedulePreferencesView()
                case .workoutEditor(let plan):
                    WorkoutPlanEditor(plan: plan, onStart: { plan in
                        handleEditorStart(plan)
                        path = NavigationPath()
                    })
                case .customExercises: CustomExerciseListView()
                case .runAssessment(let kind): AssessmentDetailView(kind: kind)
                }
            }
    }
}
