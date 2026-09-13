import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

/// Structured, deterministic plan generation from existing app controls. The
/// Plan tab uses the unified coach boundary so generated plans carry rationale,
/// provenance, and the same report used by coach review.
struct StructuredPlanGeneratorView: View {
    let onGenerated: (Plan) -> Void

    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \.WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]
    @Query(sort: \.CardioWorkout.start, order: .reverse) private var cardio: [CardioWorkout]
    @Query(sort: \.Assessment.date, order: .reverse) private var assessments: [Assessment]
    @Query(sort: \.ReadinessEntry.date, order: .reverse) private var readiness: [ReadinessEntry]
    @State private var isGenerating = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("The unified coach uses your goal, schedule, recent training, readiness, and the exercise catalog to build a reviewable draft.")
                        .font(.subheadline)
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
        let now = Date()
        let trainingFacts = TrainingFacts.make(
            sessions: sessions, assessments: assessments, now: now,
            goal: settingsSnapshot.trainingGoal,
            experience: settingsSnapshot.experienceLevel,
            formula: settingsSnapshot.formula)
        let events = CoachSnapshotBuilder.trainingEvents(
            sessions: sessions, cardio: cardio, assessments: assessments,
            formula: settingsSnapshot.formula, userAge: settingsSnapshot.userAge)
        let coachFacts = CoachFacts.make(
            from: events, goal: settingsSnapshot.trainingGoal,
            experience: settingsSnapshot.experienceLevel,
            assessments: AssessmentMath.summaries(from: assessments),
            readinessEntry: readiness.first, formula: settingsSnapshot.formula,
            now: now)
        let request = UnifiedPlanCoachRequest(
            goal: settingsSnapshot.trainingGoal,
            experience: settingsSnapshot.experienceLevel,
            schedulePreferences: settingsSnapshot.coachSchedulePreferences,
            title: "Coach plan", referenceDate: now,
            trainingFacts: trainingFacts, coachFacts: coachFacts)
        Task {
            let bundle = await Task.detached(priority: .userInitiated) {
                try? UnifiedPlanCoachEngine.generate(request)
            }.value
            guard !Task.isCancelled else { return }
            if let bundle {
                onGenerated(bundle.plan)
                dismiss()
            } else {
                message = "The unified coach could not generate an eligible plan from the current history."
                isGenerating = false
            }
        }
    }
}
