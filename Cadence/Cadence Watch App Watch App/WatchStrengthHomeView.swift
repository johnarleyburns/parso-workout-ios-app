import SwiftUI
import WatchConnectivity
import CadenceCore
import CadenceFeatures

struct WatchStrengthHomeView: View {
    let model: WatchStrengthFlowModel
    @State private var pendingExerciseID: UUID?
    @State private var showingDeleteWorkoutConfirm = false

    var body: some View {
        List {
            Section {
                ForEach(model.exerciseList, id: \.exercise.persistentModelID) { item in
                    HStack(spacing: 6) {
                        Button {
                            WatchHaptics.tap()
                            pendingExerciseID = item.exercise.id
                            DispatchQueue.main.async {
                                model.startLogSet(for: item.exercise)
                                pendingExerciseID = nil
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 5) {
                                    Text(item.exercise.name).lineLimit(1)
                                    if pendingExerciseID == item.exercise.id {
                                        ProgressView()
                                            .controlSize(.mini)
                                            .accessibilityIdentifier("watchStrength.exercise.loading")
                                    }
                                }
                                if item.setCount > 0 {
                                    Text("\(item.setCount) set\(item.setCount == 1 ? "" : "s")")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("watchStrength.exercise.\(item.exercise.name)")

                        Button(role: .destructive) {
                            WatchHaptics.delete()
                            if model.deleteExercise(item.exercise) != nil {
                                sendSync()
                            }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("watchStrength.deleteExercise.\(item.exercise.name)")
                    }
                }

                Button {
                    WatchHaptics.tap()
                    model.goToAddExercise()
                } label: {
                    Label("Add exercise", systemImage: "plus")
                }
                .accessibilityIdentifier("watchStrength.addExercise")

                if !model.partners.isEmpty {
                    Button {
                        WatchHaptics.tap()
                        model.goToPartners()
                    } label: {
                        Label("Partners", systemImage: "person.2")
                    }
                    .accessibilityIdentifier("watchStrength.partners")
                }

                Button {
                    WatchHaptics.success()
                    model.finish()
                } label: {
                    Label("Finish & Save", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                .accessibilityIdentifier("watchStrength.finish")
            }

            Section {
                Button(role: .destructive) {
                    WatchHaptics.tap()
                    showingDeleteWorkoutConfirm = true
                } label: {
                    Label("Delete Workout", systemImage: "trash")
                }
                .accessibilityIdentifier("watchStrength.deleteWorkout")
            }
        }
        .navigationTitle("Strength")
        .alert("Delete Workout?", isPresented: $showingDeleteWorkoutConfirm) {
            Button("Delete", role: .destructive) {
                WatchHaptics.delete()
                model.cancel()
            }
            .accessibilityIdentifier("watchStrength.deleteWorkout.confirm")
            Button("Keep Workout", role: .cancel) {}
                .accessibilityIdentifier("watchStrength.deleteWorkout.cancel")
        } message: {
            Text("This removes the workout and all sets logged on the watch.")
        }
    }

    private func sendSync() {
        guard let payload = model.lastSyncPayload else { return }
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        WCSession.default.transferUserInfo(payload)
    }
}
