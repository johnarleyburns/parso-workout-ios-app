import SwiftUI
import WatchKit
import CadenceCore
import CadenceFeatures

/// Dedicated weight entry. Plate math lives here, while the exact-value keypad
/// is one more tap away from the large current value.
struct WatchWeightEntryView: View {
    @Binding var value: Double
    let unit: MeasurementUnitPreference
    @Environment(\.dismiss) private var dismiss
    @State private var plate: Double = 2.5
    @State private var directEntry = false

    private var increment: WeightIncrement { WeightIncrement(unit: unit) }
    private var range: ClosedRange<Double> { increment.range }

    var body: some View {
        List {
            Section {
                Button { directEntry = true } label: {
                    VStack(spacing: 2) {
                        Text(Format.weightValue(value, unit: unit, decimals: 1))
                            .font(.system(.largeTitle, design: .rounded).weight(.bold))
                            .monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.55)
                        Text("Tap again to type exact weight")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 62)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("watchWeight.entry.value")
            }
            Section("Plate math") {
                Picker("Plate step", selection: $plate) {
                    ForEach(increment.plateOptions, id: \.self) { option in
                        Text("\(plateText(option)) \(unit.abbreviation)").tag(option)
                    }
                }
                HStack(spacing: 8) {
                    Button { adjust(-plate) } label: { Label("Subtract", systemImage: "minus") }
                        .accessibilityIdentifier("watchWeight.minusPlate")
                    Button { adjust(plate) } label: { Label("Add", systemImage: "plus") }
                        .accessibilityIdentifier("watchWeight.plusPlate")
                }
                .buttonStyle(.bordered)
            }
        }
        .navigationTitle("Weight")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .onAppear {
            plate = increment.plateOptions.filter { $0 >= (unit == .pounds ? 5 : 2.5) }.min()
                ?? increment.plateOptions.min() ?? 2.5
        }
        .sheet(isPresented: $directEntry) {
            WatchNumericEntryView(title: "Enter weight", initialValue: Format.weightValue(value, unit: unit, decimals: 1), allowsDecimal: true) { text in
                if let number = Double(text), number.isFinite {
                    value = min(range.upperBound, max(range.lowerBound, number))
                }
            }
        }
    }

    private func adjust(_ amount: Double) {
        WatchHaptics.tap()
        value = min(range.upperBound, max(range.lowerBound, value + amount))
    }

    private func plateText(_ value: Double) -> String {
        value == value.rounded() ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }
}

/// Dedicated reps entry. The number is editable through the same second-tap
/// interaction as weight, while the common +/- path remains one touch away.
struct WatchRepsEntryView: View {
    @Binding var value: Double
    @Environment(\.dismiss) private var dismiss
    @State private var directEntry = false

    var body: some View {
        List {
            Section {
                Button { directEntry = true } label: {
                    VStack(spacing: 2) {
                        Text("\(Int(value.rounded()))")
                            .font(.system(.largeTitle, design: .rounded).weight(.bold))
                            .monospacedDigit()
                        Text("Tap again to type reps")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 62)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("watchReps.entry.value")
            }
            Section("Adjust reps") {
                HStack(spacing: 8) {
                    Button { value = max(1, value - 1); WatchHaptics.tap() } label: { Label("Minus", systemImage: "minus") }
                        .accessibilityIdentifier("watchReps.minus")
                    Button { value = min(100, value + 1); WatchHaptics.tap() } label: { Label("Plus", systemImage: "plus") }
                        .accessibilityIdentifier("watchReps.plus")
                }
                .buttonStyle(.bordered)
            }
        }
        .navigationTitle("Reps")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .sheet(isPresented: $directEntry) {
            WatchNumericEntryView(title: "Enter reps", initialValue: "\(Int(value.rounded()))", allowsDecimal: false) { text in
                if let number = Int(text) { value = Double(min(100, max(1, number))) }
            }
        }
    }
}

/// A tiny numeric keypad that works consistently on the watch simulator and
/// device instead of relying on the system keyboard appearing over a compact
/// sheet.
struct WatchNumericEntryView: View {
    let title: String
    let initialValue: String
    let allowsDecimal: Bool
    let onCommit: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    private var rows: [[String]] {
        allowsDecimal ? [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], [".", "0", "⌫"]]
            : [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["", "0", "⌫"]]
    }

    var body: some View {
        VStack(spacing: 6) {
            Text(text.isEmpty ? initialValue : text)
                .font(.system(.title, design: .rounded).weight(.bold))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, minHeight: 34)
                .accessibilityIdentifier("watchNumeric.value")
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 5) {
                    ForEach(row, id: \.self) { key in
                        Button { tap(key) } label: {
                            Text(key).font(.headline).frame(maxWidth: .infinity, minHeight: 34)
                        }
                        .buttonStyle(.bordered)
                        .disabled(key.isEmpty)
                    }
                }
            }
            Button("Done") { onCommit(text.isEmpty ? initialValue : text); dismiss() }
                .buttonStyle(WatchPillStyle(kind: .primary, small: true))
                .accessibilityIdentifier("watchNumeric.done")
        }
        .padding(8)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { text = initialValue }
    }

    private func tap(_ key: String) {
        switch key {
        case "⌫": if !text.isEmpty { text.removeLast() }
        case ".": if allowsDecimal && !text.contains(".") { text += text.isEmpty ? "0." : "." }
        default: if text == "0" { text = key } else if text.count < 7 { text += key }
        }
    }
}
