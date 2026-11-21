import SwiftUI
import CadenceFeatures
import CadenceWorkoutFeatures
import CadencePhoneFeatures

extension WorkoutPlanEditor {
    /// The given performer's sets on the plan's first exercise -- the same
    /// sets the rep-structure sheet edits and the summary label describes.
    func repStructureSets(for performerID: UUID?) -> [EditableSet] {
        let first = plan.exercises.first
        return performerID == nil ? (first?.sets ?? [])
            : (first?.performerPlans.first { $0.performerID == performerID }?.sets ?? [])
    }

    var workoutRepStructureControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Workout rep structure").font(.headline)
                Spacer()
                Button { showRepStructureInfo = true } label: {
                    Image(systemName: "info.circle")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("About workout rep structure")
                .accessibilityIdentifier("editor.repStructureInfo")
            }
            ForEach(rosterMembers(), id: \.performerID) { person in
                let sets = repStructureSets(for: person.performerID)
                Button {
                    repStructurePerformer = EditablePerformerPlan(
                        performerID: person.performerID, name: person.name, sets: sets)
                } label: {
                    Label(
                        WorkoutPlanRepSchemeOptions.summary(name: person.name, reps: sets.map(\.targetReps)),
                        systemImage: "list.number")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Change workout rep structure for \(person.name)")
            }
        }
        .workoutPlanCard()
        .alert("Workout rep structure", isPresented: $showRepStructureInfo) {
            Button("Got it", role: .cancel) {}
        } message: {
            Text("Choose a structure for each person. It applies to every exercise and keeps their planned loads.")
        }
        .sheet(item: $repStructurePerformer) { person in
            RepSchemeSheet(current: person.sets.map(\.targetReps)) { reps in
                plan.applyRepStructure(reps, performerID: person.performerID)
                // A deliberate owner rep structure must not be replaced if
                // catalog/history arrives after this point.
                if person.performerID == nil {
                    seededHistoryNames.formUnion(plan.exercises.map(\.name))
                }
            }
        }
    }
}
