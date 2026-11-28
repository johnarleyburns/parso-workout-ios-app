import SwiftUI
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures
import CadencePhoneFeatures

/// The plan screen keeps the exercise list front and centre. Everything that
/// used to sit above it (partners, rep structure, rationale) and the settings
/// gear live behind the trailing overflow menu instead.
extension WorkoutPlanEditor {
    @ViewBuilder
    var planOverflowMenu: some View {
        Button { settingsPresented = true } label: {
            Label("Workout settings", systemImage: "gearshape")
        }
        .accessibilityIdentifier("editor.showSettings")
        Button { partnersPresented = true } label: {
            Label("Training Partners", systemImage: "person.2")
        }
        .accessibilityIdentifier("editor.showPartners")
        Button { repsPresented = true } label: {
            Label("Reps", systemImage: "ruler")
        }
        .accessibilityIdentifier("editor.showRepStructure")
        if plan.recommendationRationale != nil {
            Button { whyPresented = true } label: {
                Label("Why this workout", systemImage: "questionmark.circle")
            }
            .accessibilityIdentifier("editor.showRationale")
        }
    }

    @ViewBuilder
    var planPartnersSheet: some View {
        NavigationStack {
            ScrollView {
                WorkoutPlanPartnerSection(partnerIDs: $plan.partnerIDs,
                                          allPeople: allPeople,
                                          onRosterChanged: resolvePartnerPlans)
                    .padding(CGFloat(LayoutMetrics.pagePadding))
            }
            .navigationTitle("Training Partners")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { partnersPresented = false }
                }
            }
        }
    }

    @ViewBuilder
    var planRepsSheet: some View {
        NavigationStack {
            ScrollView {
                workoutRepStructureControls
                    .padding(CGFloat(LayoutMetrics.pagePadding))
            }
            .navigationTitle("Reps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { repsPresented = false }
                }
            }
        }
    }

    @ViewBuilder
    var planWhySheet: some View {
        NavigationStack {
            ScrollView {
                if let rationale = plan.recommendationRationale {
                    RecommendationRationaleDisclosure(rationale: rationale)
                        .workoutPlanCard()
                        .padding(CGFloat(LayoutMetrics.pagePadding))
                }
            }
            .navigationTitle("Why this workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { whyPresented = false }
                }
            }
        }
    }

    @ViewBuilder
    func planExerciseDetailSheet(_ exercise: Exercise) -> some View {
        NavigationStack {
            ExerciseDetailView(exercise: exercise)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { detailExercise = nil }
                    }
                }
        }
    }
}
