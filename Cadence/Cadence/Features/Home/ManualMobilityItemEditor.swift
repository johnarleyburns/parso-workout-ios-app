import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

// MARK: - Mobility item editor

enum ManualMobilityTarget: String, CaseIterable, Identifiable {
    case duration = "Seconds"
    case repetitions = "Reps"
    case distance = "Meters"

    var id: String { rawValue }
}

struct ManualMobilityItemEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var item: MobilityItem
    @State private var name: String
    @State private var roundsText: String
    @State private var target: ManualMobilityTarget
    @State private var valueText: String
    @State private var eachSide: Bool
    @State private var instructions: String
    let onSave: (WorkoutItem) -> Void

    init(item: MobilityItem, onSave: @escaping (WorkoutItem) -> Void) {
        self._item = State(initialValue: item)
        self._name = State(initialValue: item.name)
        self._roundsText = State(initialValue: item.rounds.map(String.init) ?? "")
        self._eachSide = State(initialValue: item.eachSide)
        self._instructions = State(initialValue: item.instructions ?? "")
        switch item.perRound {
        case let .duration(seconds):
            self._target = State(initialValue: .duration)
            self._valueText = State(initialValue: String(seconds))
        case let .distance(meters):
            self._target = State(initialValue: .distance)
            self._valueText = State(initialValue: String(meters))
        case let .exact(reps):
            self._target = State(initialValue: .repetitions)
            self._valueText = State(initialValue: String(reps))
        case let .range(minimum, _):
            self._target = State(initialValue: .repetitions)
            self._valueText = State(initialValue: String(minimum))
        case let .amrap(minimum):
            self._target = State(initialValue: .repetitions)
            self._valueText = State(initialValue: String(minimum ?? 1))
        }
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Mobility") {
                    TextField("Name", text: $name)
                    TextField("Rounds (optional)", text: $roundsText)
                        .keyboardType(.numberPad)
                    Toggle("Repeat each side", isOn: $eachSide)
                }
                Section("Dose") {
                    Picker("Per round", selection: $target) {
                        ForEach(ManualMobilityTarget.allCases) { value in
                            Text(value.rawValue).tag(value)
                        }
                    }
                    TextField("Amount", text: $valueText)
                        .keyboardType(.decimalPad)
                }
                Section("Instructions") {
                    TextField("Optional coaching cue", text: $instructions,
                              axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .navigationTitle("Mobility item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("manualMobility.save")
                }
            }
        }
    }

    private func save() {
        let amount = max(1, Double(valueText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 30)
        let perRound: RepTarget
        switch target {
        case .duration: perRound = .duration(seconds: Int(amount.rounded()))
        case .repetitions: perRound = .exact(Int(amount.rounded()))
        case .distance: perRound = .distance(meters: amount)
        }
        item.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        item.rounds = Int(roundsText.trimmingCharacters(in: .whitespacesAndNewlines))
        item.perRound = perRound
        item.eachSide = eachSide
        item.instructions = instructions.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        onSave(.mobility(item))
    }
}

// MARK: - Instruction item editor

struct ManualInstructionItemEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var item: InstructionItem
    let onSave: (WorkoutItem) -> Void

    init(item: InstructionItem, onSave: @escaping (WorkoutItem) -> Void) {
        self._item = State(initialValue: item)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Instruction") {
                    TextEditor(text: $item.text)
                        .frame(minHeight: 140)
                        .accessibilityIdentifier("manualInstruction.text")
                }
                Section {
                    Text("Instructions are saved in the plan and shown as a cue when the session is reviewed or handed to a compatible execution surface.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Instruction item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        item.text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !item.text.isEmpty { onSave(.instruction(item)) }
                    }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("manualInstruction.save")
                }
            }
        }
    }
}
