import SwiftUI
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures

/// Full cardio catalog reached by the compact launcher's More.. choice.
/// Weekly review remains exclusively in the Cardio tab.
struct CardioTypePickerView: View {
    let onSelect: (WorkoutType) -> Void
    let onOther: (String, Bool) -> Void

    var body: some View {
        List {
            ForEach(WorkoutType.allCases.filter { $0 != .weights && $0 != .other }) { type in
                Button { onSelect(type) } label: {
                    Label(type.displayName, systemImage: type.symbol)
                        .frame(minHeight: 44)
                }
                .accessibilityIdentifier("cardioType.\(type.rawValue)")
            }
            NavigationLink {
                OtherCardioEntryView(onStart: onOther)
            } label: { Label(WorkoutType.other.displayName, systemImage: WorkoutType.other.symbol) }
        }
        .navigationTitle("Cardio")
    }
}
