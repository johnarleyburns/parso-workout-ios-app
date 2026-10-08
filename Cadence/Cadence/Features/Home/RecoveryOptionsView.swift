import SwiftUI
import CadenceCore
import CadenceFeatures

struct RecoveryOptionsView: View {
    let onResistance: (EditablePlan) -> Void
    let onCardio: (CoachSession) -> Void
    let onChooseWorkout: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Keep these optional sessions light. Review the setup before starting, and shorten or stop if you feel uncomfortable.")
                        .foregroundStyle(.secondary)
                }
                Section("Light resistance") {
                    Button {
                        onResistance(RecoveryOptionsPresenter.resistancePlan())
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Light resistance")
                            Text("1 × 8 bodyweight squats and incline push-ups against a wall or high support · no added weight · at least 5 reps left in reserve")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Easy cardio") {
                    ForEach(RecoveryOptionsPresenter.cardio) { session in
                        Button { onCardio(session) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(session.title)
                                Text(session.subtitle).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section {
                    CoachSourcesLink(citationIds: RecoveryOptionsPresenter.citationIDs,
                                     contexts: [:], identifier: "home.recovery.science")
                    Button("Choose any workout", action: onChooseWorkout)
                }
            }
            .navigationTitle("Easy options")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
    }
}

extension HomeView {
    var recoveryOptionsSheet: some View {
        RecoveryOptionsView(
            onResistance: { plan in
                recoveryOptionsPresented = false
                Task { @MainActor in
                    await Task.yield()
                    workoutEditorPlan = plan
                }
            },
            onCardio: { session in
                recoveryOptionsPresented = false
                Task { @MainActor in
                    await Task.yield()
                    launchDecision(session)
                }
            },
            onChooseWorkout: {
                recoveryOptionsPresented = false
                Task { @MainActor in
                    await Task.yield()
                    selectWorkoutPresented = true
                }
            })
    }
}
