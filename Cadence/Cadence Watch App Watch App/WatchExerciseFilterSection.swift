import SwiftUI
import CadenceCore
import CadenceFeatures

/// Compound/isolation and equipment pickers that narrow a Watch muscle-group list.
struct WatchExerciseFilterSection: View {
    @Binding var filter: WatchExerciseFilter
    let entries: [ExerciseCatalogEntry]

    var body: some View {
        Section("Filter") {
            Picker("Type", selection: $filter.mechanics) {
                Text("Any").tag(Mechanics?.none)
                Text("Compound").tag(Mechanics?.some(.compound))
                Text("Isolation").tag(Mechanics?.some(.isolation))
            }
            .accessibilityIdentifier("watchAddExercise.filter.type")
            Picker("Equipment", selection: $filter.equipment) {
                Text("Any").tag(Equipment?.none)
                ForEach(filter.availableEquipment(in: entries)) { item in
                    Text(item.displayName).tag(Equipment?.some(item))
                }
            }
            .accessibilityIdentifier("watchAddExercise.filter.equipment")
        }
    }
}
