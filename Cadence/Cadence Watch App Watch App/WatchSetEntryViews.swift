import SwiftUI
import WatchKit
import CadenceCore
import CadenceFeatures

/// Reusable numeric entry sheet for set weight / reps. A custom keypad (no `TextField`/`TextFieldLink`)
/// so a full keyboard can never appear; `WatchNumericKeypad` enforces digits / one separator / 2 decimals.
/// Done hands the raw text to `WatchSetEntryParser`, the final range authority; Cancel changes nothing.
struct WatchNumericEntrySheet: View {
    let field: WatchNumericField
    let title: Text
    let submit: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text: String

    init(field: WatchNumericField, initial: String, title: Text, submit: @escaping (String) -> Void) {
        self.field = field
        self.title = title
        self.submit = submit
        self._text = State(initialValue: initial)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 4) {
                title.font(.caption2).foregroundStyle(.secondary)
                Text(text.isEmpty ? "0" : text)
                    .font(.system(.title3, design: .rounded).weight(.bold)).monospacedDigit()
                    .accessibilityIdentifier("watchNumeric.display")
                    .accessibilityLabel(Text("Value"))
                    .accessibilityValue(Text(text.isEmpty ? "0" : text))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 3), spacing: 3) {
                    ForEach(WatchNumericKeypad.keys, id: \.self) { key in
                        Button { text = WatchNumericKeypad.apply(key, to: text, field: field) } label: {
                            Text(key).font(.headline).frame(maxWidth: .infinity, minHeight: 32)
                        }
                        .disabled(key == "." && field == .reps)
                        .accessibilityLabel(Self.label(for: key))
                        .accessibilityIdentifier("watchNumeric.key.\(key == "⌫" ? "backspace" : key == "." ? "decimal" : key)")
                    }
                }
                HStack(spacing: 4) {
                    Button("Cancel", role: .cancel) { dismiss() }
                        .accessibilityIdentifier("watchNumeric.cancel")
                    Button("Done") { dismiss(); submit(text) }
                        .accessibilityIdentifier("watchNumeric.done")
                }
            }
        }
    }

    private static func label(for key: String) -> Text {
        switch key {
        case "⌫": Text("Delete")
        case ".": Text("Decimal point")
        default: Text(verbatim: key)
        }
    }
}

/// Weight adjustment without a keypad: one selected plate step with large − / + buttons.
/// Lives in More; exact entry is the Set Card's native weight link.
struct WatchWeightAdjustSection: View {
    @Binding var value: Double
    let unit: MeasurementUnitPreference
    @Binding var plate: Double
    @State private var plateStepPicker = false

    init(value: Binding<Double>, unit: MeasurementUnitPreference, plate: Binding<Double>) {
        self._value = value
        self.unit = unit
        self._plate = plate
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
