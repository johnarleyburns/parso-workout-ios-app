import SwiftUI
import CadenceCore
import CadenceFeatures

/// Structured, deterministic plan generation from existing app controls. There
/// is no text parser here: the engine receives the user's stored goal, schedule,
/// experience, equipment vocabulary, and a style bias.
struct StructuredPlanGeneratorView: View {
    let onGenerated: (EditablePlan) -> Void

    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var style: SuggestedWorkoutStyle = .fitness
    @State private var isGenerating = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Movement style", selection: $style) {
                        ForEach(SuggestedWorkoutStyle.allCases, id: \.rawValue) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .accessibilityIdentifier("structuredPlan.style")
                    Text(style.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Generate a plan")
                } footer: {
                    Text("Uses your \(settings.trainingGoal.displayName.lowercased()) goal, \(settings.experienceLevel.displayName.lowercased()) experience, weekly schedule, and available exercise catalog.")
                }

                Section {
                    Button {
                        generate()
                    } label: {
                        HStack {
                            if isGenerating {
                                ProgressView()
                            }
                            Text(isGenerating ? "Generating…" : "Generate")
                        }
                    }
                    .disabled(isGenerating)
                    .accessibilityIdentifier("structuredPlan.generate")
                }

                if let message {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("structuredPlan.message")
                    }
                }
            }
            .navigationTitle("Coach Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("structuredPlan.cancel")
                }
            }
        }
    }

    private func generate() {
        message = nil
        isGenerating = true
        let settingsSnapshot = settings
        let input = SuggestedWorkoutInput(
            completedSetsByMuscle: [:],
            candidates: [],
            trackedGroups: settingsSnapshot.coachSchedulePreferences.trackedMuscleGroups,
            preferredSetsPerExercise: settingsSnapshot.coachSchedulePreferences.desiredSetsPerExercise,
            trainingGoal: settingsSnapshot.trainingGoal,
            engineContext: SuggestedWorkoutEngineContext(
                experience: settingsSnapshot.experienceLevel,
                schedule: settingsSnapshot.coachSchedulePreferences,
                availableEquipment: Equipment.allCases,
                environment: "commercial_gym"))
        Task {
            let bundle = await Task.detached(priority: .userInitiated) {
                SuggestedWorkoutGenerator.generate(input: input)
            }.value
            guard !Task.isCancelled else { return }
            let option = bundle.option(style)
            if option.isLaunchable {
                let draft = SuggestedWorkoutPresenter.editablePlan(
                    for: option,
                    unit: settingsSnapshot.unit,
                    warmupMinutes: settingsSnapshot.warmupMinutes,
                    cooldownMinutes: settingsSnapshot.cooldownMinutes)
                onGenerated(draft)
            } else {
                message = "The engine could not find an eligible movement for this request."
                isGenerating = false
            }
        }
    }
}
