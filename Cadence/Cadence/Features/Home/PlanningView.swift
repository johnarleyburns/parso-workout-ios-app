import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

struct PlanningView: View {
    let switchToWorkout: () -> Void
    /// Opens the Coach preview. Present in every coach surface state (including
    /// `hidden`), so the coach is always reachable from Programs (design §2/§8).
    var onOpenCoach: (() -> Void)? = nil

    @Environment(\.modelContext) var context
    @Environment(ActiveWorkoutModel.self) var active
    @Environment(AppSettings.self) var settings
    @Query(sort: \Exercise.name) var exercises: [Exercise]
    @Query(sort: \SessionTemplate.name) var templates: [SessionTemplate]
    @Query(sort: \PersistedPlan.updatedAt, order: .reverse) var persistedPlans: [PersistedPlan]

    @State var segment: Segment = .routines
    @State var query = ""
    @State var selectedGroup: MuscleGroup?
    @State var browseAll = false
    @State var templateEditorPresented = false
    @State var manualPlan: Plan?
    @State var combinedLaunch: CombinedSessionLaunch?
    /// The exercise catalog is a SwiftData graph. Keep its normalized search
    /// representation outside the view's computed properties so typing does not
    /// rebuild and re-rank every row on every SwiftUI redraw.
    @State var exerciseSearchIndex = ExerciseSearchIndex<Exercise>([])
    @State var exerciseSearchIndexedCount = -1

    enum Segment: String, CaseIterable { case routines, exercises }
    @State var routineInfoSheet: RoutineInfo?

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $segment) {
                Text("Routines").tag(Segment.routines)
                Text("Exercises").tag(Segment.exercises)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal).padding(.top, 8).padding(.bottom, 4)

            switch segment {
            case .routines: routinesList
            case .exercises: exercisesList
            }
        }
        .navigationTitle("Plan")
        .searchable(text: $query,
                    prompt: segment == .exercises
                        ? "Search name, muscle, or equipment"
                        : "Search routines")
        .onChange(of: segment) { _, _ in
            query = ""
            selectedGroup = nil
            browseAll = false
        }
        .onAppear { rebuildExerciseSearchIndexIfNeeded() }
        .onChange(of: exercises.count) { _, _ in rebuildExerciseSearchIndexIfNeeded() }
        .sheet(isPresented: $templateEditorPresented) { TemplateEditorView() }
        .sheet(item: $manualPlan) { plan in
            ManualPlanView(plan: plan, onStart: startAuthoredSession)
        }
        .sheet(item: $combinedLaunch) { launch in
            CombinedPlanRunnerView(session: launch.session, lease: launch.lease) {
                combinedLaunch = nil
                switchToWorkout()
            }
        }
        .accessibilityIdentifier("planning")
    }

    }
