import SwiftUI
import WatchConnectivity
import CadenceCore
import CadenceFeatures

struct WatchStrengthHomeView: View {
    let model: WatchStrengthFlowModel

    var body: some View {
        List {
            Section {
                ForEach(model.exerciseList, id: \.exercise.persistentModelID) { item in
                    HStack(spacing: 6) {
                        Button {
                            WatchHaptics.tap()
                            model.startLogSet(for: item.exercise)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.exercise.name).lineLimit(1)
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
                Button(role: .destructive) {
                    WatchHaptics.delete()
                    model.cancel()
                } label: {
                    Label("Cancel", systemImage: "xmark.circle.fill")
                }
                .accessibilityIdentifier("watchStrength.cancel")
            }
        }
        .navigationTitle("Strength")
    }

    private func sendSync() {
        guard let payload = model.lastSyncPayload else { return }
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        WCSession.default.transferUserInfo(payload)
    }
}
