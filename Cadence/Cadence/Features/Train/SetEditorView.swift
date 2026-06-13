import SwiftUI
import CadenceCore

/// Add or edit a single set (FR-1.2, FR-1.7). Field-testing §04: weight can be
/// entered in EITHER lb or kg with the other auto-filled, and the set can be
/// attributed to a training partner. Storage stays canonical kg.
struct SetEditorView: View {
    let exerciseName: String
    let unit: MeasurementUnitPreference
    let lastTimeText: String?
    let prText: String?
    /// Roster for attribution (owner first, then partners). Empty ⇒ owner-only.
    let people: [Person]
    /// Snap the saved weight to the nearest plate (decision #15, default off).
    let plateRounding: Bool
    /// The movement is a bodyweight exercise (feedback batch 3): default to a
    /// bodyweight set and treat the weight field as *added* load.
    let isBodyweightExercise: Bool
    let onSave: (_ weightKg: Double, _ reps: Int, _ rpe: Double?, _ isWarmup: Bool, _ usesBodyweight: Bool, _ note: String?, _ performedBy: Person?) -> Void
    var onDelete: (() -> Void)? = nil

    /// Whether the current entry would set a new PR (live, FR-1.4).
    private let prCheck: (Double, Int, Bool) -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var weightText: String      // primary, in `unit`
    @State private var altText: String         // opposite unit, auto-filled
    @State private var reps: Int
    @State private var isWarmup: Bool
    @State private var usesBodyweight: Bool
    @State private var note: String
    @State private var performedByID: UUID?    // nil ⇒ owner

    private var oppositeUnit: MeasurementUnitPreference { unit == .kilograms ? .pounds : .kilograms }

    init(exerciseName: String,
         unit: MeasurementUnitPreference,
         lastTimeText: String? = nil,
         prText: String? = nil,
         people: [Person] = [],
         plateRounding: Bool = false,
         isBodyweightExercise: Bool = false,
         initialWeightKg: Double = 0,
         initialReps: Int = 5,
         initialRPE: Double? = nil,
         initialWarmup: Bool = false,
         initialBodyweight: Bool = false,
         initialNote: String? = nil,
         initialPerformedBy: Person? = nil,
         isPRPredicate: @escaping (Double, Int, Bool) -> Bool = { _, _, _ in false },
         onSave: @escaping (Double, Int, Double?, Bool, Bool, String?, Person?) -> Void,
         onDelete: (() -> Void)? = nil) {
        self.exerciseName = exerciseName
        self.unit = unit
        self.lastTimeText = lastTimeText
        self.prText = prText
        self.people = people
        self.plateRounding = plateRounding
        self.isBodyweightExercise = isBodyweightExercise
        self.prCheck = isPRPredicate
        self.onSave = onSave
        self.onDelete = onDelete
        let primary = initialWeightKg > 0 ? Format.weightValue(initialWeightKg, unit: unit) : ""
        let alt = initialWeightKg > 0 ? Format.weightValue(initialWeightKg, unit: unit == .kilograms ? .pounds : .kilograms) : ""
        _weightText = State(initialValue: primary)
        _altText = State(initialValue: alt)
        _reps = State(initialValue: initialReps)
        _isWarmup = State(initialValue: initialWarmup)
        _usesBodyweight = State(initialValue: initialBodyweight)
        _note = State(initialValue: initialNote ?? "")
        _performedByID = State(initialValue: initialPerformedBy.flatMap { $0.isMe ? nil : $0.id })
    }

    private func parse(_ s: String) -> Double? {
        Double(s.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
    }
    private var weightKg: Double {
        WorkoutMath.canonical(parse(weightText) ?? 0, from: unit)
    }
    /// A bodyweight set may be saved with no added load; a regular set needs a weight.
    private var canSave: Bool { weightKg >= 0 && reps > 0 && (usesBodyweight || !weightText.isEmpty) }
    private var weightLabel: String { usesBodyweight ? "Added" : "Weight" }
    private var wouldBePR: Bool { canSave && prCheck(weightKg, reps, isWarmup) }
    private var partners: [Person] { people.filter { !$0.isMe } }
    private var selectedPerson: Person? { people.first { $0.id == performedByID } }

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
                    if isBodyweightExercise {
                        Toggle("Bodyweight", isOn: $usesBodyweight)
                            .accessibilityIdentifier("set.bodyweight")
                    }
                    HStack {
                        Text("\(weightLabel) (\(unit.abbreviation))")
                        Spacer()
                        TextField(usesBodyweight ? "0 (BW)" : "0", text: $weightText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 110)
                            .accessibilityIdentifier("set.weight")
                            .onChange(of: weightText) { _, new in syncAlt(from: new) }
                    }
                    HStack {
                        Text("\(weightLabel) (\(oppositeUnit.abbreviation))")
                            .foregroundStyle(.secondary)
                        Spacer()
                        TextField(usesBodyweight ? "0 (BW)" : "0", text: $altText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 110)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("set.weight.alt")
                            .onChange(of: altText) { _, new in syncPrimary(from: new) }
                    }
                    Stepper(value: $reps, in: 1...100) {
                        HStack { Text("Reps"); Spacer(); Text("\(reps)").monospacedDigit() }
                    }
                    .accessibilityIdentifier("set.reps")

                    Toggle("Warmup", isOn: $isWarmup)
                        .accessibilityIdentifier("set.warmup")
                }

                if !partners.isEmpty {
                    Section("For") {
                        Picker("Performed by", selection: $performedByID) {
                            Text("Me").tag(UUID?.none)
                            ForEach(partners) { p in
                                Text(p.name).tag(UUID?.some(p.id))
                            }
                        }
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("set.performedBy")
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
                    Button("Record") {
                        let kg = plateRounding ? UnitEntry.plateRounded(kg: weightKg, unit: unit) : weightKg
                        onSave(kg, reps, nil, isWarmup, usesBodyweight,
                               note.trimmingCharacters(in: .whitespaces).isEmpty ? nil : note,
                               selectedPerson)
                        dismiss()
                    }
                    .disabled(!canSave)
                    .accessibilityIdentifier("set.save")
                }
            }
        }
    }

    // MARK: Dual-unit sync (field-testing §04, exact conversion)

    private func syncAlt(from primary: String) {
        guard let v = parse(primary) else { if primary.isEmpty { altText = "" }; return }
        let formatted = Format.weightValue(WorkoutMath.canonical(v, from: unit), unit: oppositeUnit)
        if altText != formatted { altText = formatted }
    }

    private func syncPrimary(from alt: String) {
        guard let v = parse(alt) else { if alt.isEmpty { weightText = "" }; return }
        let kg = WorkoutMath.canonical(v, from: oppositeUnit)
        let formatted = Format.weightValue(kg, unit: unit)
        if weightText != formatted { weightText = formatted }
    }
}
