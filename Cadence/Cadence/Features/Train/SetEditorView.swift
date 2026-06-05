import SwiftUI
import CadenceCore

/// Add or edit a single set (FR-1.2, FR-1.7). Weight is entered in the user's
/// unit and converted to canonical kg on save.
struct SetEditorView: View {
    let exerciseName: String
    let unit: MeasurementUnitPreference
    let lastTimeText: String?
    let prText: String?
    /// Whether the current entry would set a new PR (live, FR-1.4).
    let isPRPredicate: (Double, Int, Bool) -> Bool
    let onSave: (_ weightKg: Double, _ reps: Int, _ rpe: Double?, _ isWarmup: Bool, _ note: String?) -> Void
    var onDelete: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var weightText: String
    @State private var reps: Int
    @State private var useRPE: Bool
    @State private var rpe: Double
    @State private var isWarmup: Bool
    @State private var note: String

    init(exerciseName: String,
         unit: MeasurementUnitPreference,
         lastTimeText: String? = nil,
         prText: String? = nil,
         initialWeightKg: Double = 0,
         initialReps: Int = 5,
         initialRPE: Double? = nil,
         initialWarmup: Bool = false,
         initialNote: String? = nil,
         isPRPredicate: @escaping (Double, Int, Bool) -> Bool = { _, _, _ in false },
         onSave: @escaping (Double, Int, Double?, Bool, String?) -> Void,
         onDelete: (() -> Void)? = nil) {
        self.exerciseName = exerciseName
        self.unit = unit
        self.lastTimeText = lastTimeText
        self.prText = prText
        self.isPRPredicate = isPRPredicate
        self.onSave = onSave
        self.onDelete = onDelete
        let initialDisplay = initialWeightKg > 0 ? Format.weightValue(initialWeightKg, unit: unit) : ""
        _weightText = State(initialValue: initialDisplay)
        _reps = State(initialValue: initialReps)
        _useRPE = State(initialValue: initialRPE != nil)
        _rpe = State(initialValue: initialRPE ?? 8)
        _isWarmup = State(initialValue: initialWarmup)
        _note = State(initialValue: initialNote ?? "")
    }

    private var weightKg: Double {
        WorkoutMath.canonical(Double(weightText.replacingOccurrences(of: ",", with: ".")) ?? 0, from: unit)
    }
    private var canSave: Bool { weightKg >= 0 && reps > 0 && !weightText.isEmpty }
    private var wouldBePR: Bool { canSave && isPRPredicate(weightKg, reps, isWarmup) }

    var body: some View {
        NavigationStack {
            Form {
                if lastTimeText != nil || prText != nil {
                    Section {
                        if let lastTimeText {
                            LabeledContent("Last time", value: lastTimeText)
                                .accessibilityIdentifier("exercise.lastTime")
                        }
                        if let prText {
                            LabeledContent("PR", value: prText)
                                .accessibilityIdentifier("exercise.pr")
                        }
                    }
                }

                Section("Set") {
                    HStack {
                        Text("Weight (\(unit.abbreviation))")
                        Spacer()
                        TextField("0", text: $weightText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 120)
                            .accessibilityIdentifier("set.weight")
                    }
                    Stepper(value: $reps, in: 1...100) {
                        HStack { Text("Reps"); Spacer(); Text("\(reps)").monospacedDigit() }
                    }
                    .accessibilityIdentifier("set.reps")

                    Toggle("Warmup", isOn: $isWarmup)
                        .accessibilityIdentifier("set.warmup")

                    Toggle("Track RPE", isOn: $useRPE)
                    if useRPE {
                        VStack(alignment: .leading) {
                            Text("RPE \(rpe, specifier: "%.1f")")
                            Slider(value: $rpe, in: 1...10, step: 0.5)
                                .accessibilityIdentifier("set.rpe")
                        }
                    }
                }

                Section("Note") {
                    TextField("Optional note", text: $note, axis: .vertical)
                        .accessibilityIdentifier("set.note")
                }

                if wouldBePR {
                    Section {
                        Label("New PR", systemImage: "trophy.fill")
                            .foregroundStyle(.orange)
                            .accessibilityIdentifier("set.prPreview")
                    }
                }

                if let onDelete {
                    Section {
                        Button(role: .destructive) {
                            onDelete(); dismiss()
                        } label: { Label("Delete Set", systemImage: "trash") }
                            .accessibilityIdentifier("set.delete")
                    }
                }
            }
            .navigationTitle(exerciseName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.accessibilityIdentifier("set.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(weightKg, reps, useRPE ? rpe : nil, isWarmup,
                               note.trimmingCharacters(in: .whitespaces).isEmpty ? nil : note)
                        dismiss()
                    }
                    .disabled(!canSave)
                    .accessibilityIdentifier("set.save")
                }
            }
        }
    }
}
