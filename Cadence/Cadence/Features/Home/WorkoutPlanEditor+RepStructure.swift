import SwiftUI
import CadenceFeatures

extension WorkoutPlanEditor {
    var workoutRepStructureControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Workout rep structure").font(.headline)
            Text("Choose a structure for each person. It applies to every exercise and keeps their planned loads.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(rosterMembers(), id: \.performerID) { person in
                Button {
                    let first = plan.exercises.first
                    repStructurePerformer = EditablePerformerPlan(
                        performerID: person.performerID, name: person.name,
                        sets: person.performerID == nil ? (first?.sets ?? [])
                            : (first?.performerPlans.first { $0.performerID == person.performerID }?.sets ?? []))
                } label: {
                    Label {
                        Text(verbatim: "\(person.name): \(plan.repStructure(performerID: person.performerID).map(String.init).joined(separator: "-"))")
                    } icon: { Image(systemName: "list.number") }
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Change workout rep structure for \(person.name)")
                .accessibilityValue(plan.repStructure(performerID: person.performerID).map(String.init).joined(separator: "-"))
            }
        }
        .workoutPlanCard()
        .sheet(item: $repStructurePerformer) { person in
            RepSchemeSheet(current: person.sets.map(\.targetReps)) { reps in
                plan.applyRepStructure(reps, performerID: person.performerID)
            }
        }
    }
}
