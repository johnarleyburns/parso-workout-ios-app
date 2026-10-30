import SwiftUI
import WatchKit
import CadenceCore
import CadenceFeatures

/// Reusable native entry control for set weight / reps. `TextFieldLink` opens the system text-input
/// UI (Dictation, Scribble, keyboard, Continuity) on the Watch itself — no iPhone, Speech
/// permission or WatchConnectivity involved.
struct WatchNativeSetEntryLink<Label: View>: View {
    let prompt: Text
    let onSubmit: (String) -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        TextFieldLink(prompt: prompt, label: label, onSubmit: onSubmit)
            .buttonStyle(.plain)
    }
}

/// Weight adjustment without a keypad: one selected plate step with large − / + buttons.
/// Lives in More; exact entry is the Set Card's native weight link.
struct WatchWeightAdjustSection: View {
    @Binding var value: Double
    let unit: MeasurementUnitPreference
    @State private var plate: Double
    @State private var plateStepPicker = false

    init(value: Binding<Double>, unit: MeasurementUnitPreference) {
        self._value = value
        self.unit = unit
        let increment = WeightIncrement(unit: unit)
        self._plate = State(initialValue: increment.plateOptions.filter { $0 >= (unit == .pounds ? 5 : 2.5) }.min()
            ?? increment.plateOptions.min() ?? 2.5)
    }

    private var increment: WeightIncrement { WeightIncrement(unit: unit) }

    var body: some View {
        Section("Adjust weight") {
            Button { plateStepPicker = true } label: {
                Text("±\(plateText(plate)) \(unit.abbreviation)").frame(maxWidth: .infinity, minHeight: 40)
            }
            .accessibilityLabel("Plate step \(plateText(plate)) \(unit.abbreviation)")
            .accessibilityIdentifier("watchWeight.platePicker")
            HStack(spacing: 6) {
                Button { adjust(-plate) } label: {
                    Text("−\(plateText(plate))").font(.headline.weight(.bold)).frame(maxWidth: .infinity, minHeight: 40)
                }
                .accessibilityLabel("Subtract \(plateText(plate)) \(unit.abbreviation)")
                .accessibilityIdentifier("watchWeight.minusPlate")
                Button { adjust(plate) } label: {
                    Text("+\(plateText(plate))").font(.headline.weight(.bold)).frame(maxWidth: .infinity, minHeight: 40)
                }
                .accessibilityLabel("Add \(plateText(plate)) \(unit.abbreviation)")
                .accessibilityIdentifier("watchWeight.plusPlate")
            }
            .buttonStyle(.bordered)
        }
        .sheet(isPresented: $plateStepPicker) {
            List(increment.plateOptions, id: \.self) { option in
                Button {
                    plate = option
                    plateStepPicker = false
                } label: {
                    HStack {
                        Text("\(plateText(option)) \(unit.abbreviation)")
                        Spacer()
                        if option == plate { Image(systemName: "checkmark") }
                    }
                }
            }
            .navigationTitle("Plate step")
        }
    }

    private func adjust(_ amount: Double) {
        WatchHaptics.tap()
        value = min(increment.range.upperBound, max(increment.range.lowerBound, value + amount))
    }

    private func plateText(_ value: Double) -> String {
        value == value.rounded() ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }
}

/// Reps adjustment: −1 / +1 within the same 1…100 range direct entry accepts.
struct WatchRepsAdjustSection: View {
    @Binding var value: Double

    var body: some View {
        Section("Adjust reps") {
            HStack(spacing: 8) {
                Button { value = max(1, value - 1); WatchHaptics.tap() } label: {
                    Label("−1", systemImage: "minus").frame(maxWidth: .infinity, minHeight: 40)
                }
                .accessibilityLabel("Subtract 1 rep")
                .accessibilityIdentifier("watchReps.minus")
                Button { value = min(100, value + 1); WatchHaptics.tap() } label: {
                    Label("+1", systemImage: "plus").frame(maxWidth: .infinity, minHeight: 40)
                }
                .accessibilityLabel("Add 1 rep")
                .accessibilityIdentifier("watchReps.plus")
            }
            .buttonStyle(.bordered)
        }
    }
}
