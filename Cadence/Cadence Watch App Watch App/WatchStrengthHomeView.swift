import SwiftUI
import CadenceCore
import CadenceFeatures

struct WatchStrengthHomeView: View {
    let model: WatchStrengthFlowModel

    var body: some View {
        List {
            Section {
                ForEach(model.exerciseList, id: \.exercise.persistentModelID) { item in
                    Button {
                        model.startLogSet(for: item.exercise)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.exercise.name).lineLimit(1)
                                if item.setCount > 0 {
                                    Text("\(item.setCount) set\(item.setCount == 1 ? "" : "s")")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("watchStrength.exercise.\(item.exercise.name)")
                }

                Button { model.goToAddExercise() } label: {
                    Label("Add exercise", systemImage: "plus")
                }
                .accessibilityIdentifier("watchStrength.addExercise")

                if !model.partners.isEmpty {
                    Button { model.goToPartners() } label: {
                        Label("Partners", systemImage: "person.2")
                    }
                    .accessibilityIdentifier("watchStrength.partners")
                }

                Button { model.finish() } label: {
                    Label("Finish & Save", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                .accessibilityIdentifier("watchStrength.finish")
                Button(role: .destructive) { model.cancel() } label: {
                    Label("Cancel", systemImage: "xmark.circle.fill")
                }
                .accessibilityIdentifier("watchStrength.cancel")
            }
        }
        .navigationTitle("Strength")
    }
}
