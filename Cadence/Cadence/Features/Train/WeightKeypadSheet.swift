import SwiftUI
import CadenceCore
import CadenceFeatures

/// Large-button numeric keypad popup for logging a set's weight (feedback batch 6
/// item 2). Replaces the cramped Form-style `SetEditorView` in the live logging
/// flow: inline set rows in `SessionView` open this for fast, thumb-friendly weight
/// entry. Reps come pre-filled from the launching plan; an optional partner can be
/// attributed. No warm-up toggle — warm-up is the guided phase, not a per-set flag.
///
/// Accessibility ids mirror the old editor so tests keep targeting the same set:
/// `set.weight` (the big display, `accessibilityValue` = the raw entry),
/// `set.weight.alt` (auto-converted opposite unit), `set.reps`, `set.bodyweight`,
/// `set.performedBy`, `set.prPreview`, `set.save`, `set.delete`. Keypad keys are
/// `keypad.k.0`…`keypad.k.9`, `keypad.dot`, `keypad.back`, `keypad.clear`.
struct WeightKeypadSheet: View {
    let exerciseName: String
    let unit: MeasurementUnitPreference
    let lastTimeText: String?
    let prText: String?
    /// Roster for attribution (owner first, then partners). Empty ⇒ owner-only.
    let people: [Person]
    let plateRounding: Bool
    /// Bodyweight movement: default to a bodyweight set; weight is *added* load.
    let isBodyweightExercise: Bool
    let onSave: (_ weightKg: Double, _ reps: Int, _ usesBodyweight: Bool, _ performedBy: Person?) -> Void
    var onDelete: (() -> Void)? = nil

    private let prCheck: (Double, Int) -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var entry: String        // raw digits typed, in `unit`
    @State private var reps: Int
    @State private var usesBodyweight: Bool
    @State private var performedByID: UUID?  // nil ⇒ owner

    init(exerciseName: String,
         unit: MeasurementUnitPreference,
         lastTimeText: String? = nil,
         prText: String? = nil,
         people: [Person] = [],
         plateRounding: Bool = false,
         isBodyweightExercise: Bool = false,
         initialWeightKg: Double = 0,
         initialReps: Int = 5,
         initialBodyweight: Bool = false,
         initialPerformedBy: Person? = nil,
         isPRPredicate: @escaping (Double, Int) -> Bool = { _, _ in false },
         onSave: @escaping (Double, Int, Bool, Person?) -> Void,
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
        _entry = State(initialValue: primary)
        _reps = State(initialValue: max(1, initialReps))
        _usesBodyweight = State(initialValue: initialBodyweight)
        _performedByID = State(initialValue: initialPerformedBy.flatMap { $0.isMe ? nil : $0.id })
    }

    private var oppositeUnit: MeasurementUnitPreference { unit == .kilograms ? .pounds : .kilograms }
    private func parse(_ s: String) -> Double? { Double(s) }
    private var weightKg: Double { WorkoutMath.canonical(parse(entry) ?? 0, from: unit) }
    private var displayWeight: String {
        if !entry.isEmpty { return entry }
        return usesBodyweight ? "BW" : "0"
    }
    /// Opposite-unit read-out, auto-converted; "—" until a positive weight is typed.
    private var altText: String {
        guard let v = parse(entry), v > 0 else { return "—" }
        return "≈ " + Format.weightValue(WorkoutMath.canonical(v, from: unit), unit: oppositeUnit)
            + " " + oppositeUnit.abbreviation
    }
    // 0 kg is a valid load (e.g. an empty bar) — saving needs reps and an explicit
    // entry, but the entry may be "0" (feedback batch 7 item 5). Empty still blocks.
    private var canSave: Bool { reps > 0 && (usesBodyweight || (!entry.isEmpty && parse(entry) != nil)) }
    private var wouldBePR: Bool { canSave && prCheck(weightKg, reps) }
    private var partners: [Person] { people.filter { !$0.isMe } }
    private var selectedPerson: Person? { people.first { $0.id == performedByID } }
    private var weightLabel: String { usesBodyweight ? "Added" : "Weight" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if lastTimeText != nil || prText != nil { contextLine }

                    // Big weight read-out + auto-converted alt unit.
                    VStack(spacing: 2) {
                        Text("\(displayWeight) \(unit.abbreviation)")
                            .scaledSystemFont(56, relativeTo: .largeTitle, weight: .bold, design: .rounded)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .accessibilityIdentifier("set.weight")
                            .accessibilityLabel("\(weightLabel) \(displayWeight) \(unit.abbreviation)")
                            .accessibilityValue(entry)
                        Text(altText)
                            .font(.callout).foregroundStyle(.secondary)
                            .accessibilityIdentifier("set.weight.alt")
                    }

                    if isBodyweightExercise {
                        Toggle("Bodyweight (weight is added load)", isOn: $usesBodyweight)
                            .accessibilityIdentifier("set.bodyweight")
                            .padding(.horizontal)
                    }

                    Stepper(value: $reps, in: 1...100) {
                        HStack { Text("Reps"); Spacer(); Text("\(reps)").monospacedDigit().font(.headline) }
                    }
                    .accessibilityIdentifier("set.reps")
                    .padding(.horizontal)

                    if !partners.isEmpty {
                        Picker("For", selection: $performedByID) {
                            Text("Me").tag(UUID?.none)
                            ForEach(partners) { p in Text(p.name).tag(UUID?.some(p.id)) }
                        }
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("set.performedBy")
                        .padding(.horizontal)
                    }

                    if wouldBePR {
                        Label("New PR", systemImage: "trophy.fill")
                            .font(.subheadline.bold()).foregroundStyle(.orange)
                            .accessibilityIdentifier("set.prPreview")
                    }

                    keypad

                    if let onDelete {
                        Button(role: .destructive) {
                            onDelete(); dismiss()
                        } label: { Label("Delete Set", systemImage: "trash") }
                            .accessibilityIdentifier("set.delete")
                    }
                }
                .padding(.vertical)
            }
            // Record stays pinned and hittable regardless of keypad height.
            .safeAreaInset(edge: .bottom) {
                recordFooter
            }
            .navigationTitle(exerciseName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.accessibilityIdentifier("set.cancel")
                }
            }
        }
    }

    @ViewBuilder
    private var recordFooter: some View {
        let footer = Button {
            let kg = plateRounding ? UnitEntry.plateRounded(kg: weightKg, unit: unit) : weightKg
            onSave(kg, reps, usesBodyweight, selectedPerson)
            dismiss()
        } label: {
            Label("Record", systemImage: "checkmark").frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent).controlSize(.large)
        .disabled(!canSave)
        .accessibilityIdentifier("set.save")
        .padding(.horizontal)
        .padding(.bottom, 8)

        if GlassFeature.isEnabled, #available(iOS 26.0, *) {
            footer.glassEffect(.regular, in: Rectangle())
        } else {
            footer.background(.bar)
        }
    }

    @ViewBuilder private var contextLine: some View {
        VStack(spacing: 2) {
            if let lastTimeText {
                Text("Last: \(lastTimeText)").font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("exercise.lastTime")
            }
            if let prText {
                Text("PR: \(prText)").font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("exercise.pr")
            }
        }
    }

    // MARK: Keypad

    private let keys: [[String]] = [
        ["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], [".", "0", "⌫"]
    ]

    private var keypad: some View {
        VStack(spacing: 10) {
            HStack {
                Spacer()
                Button("Clear") { entry = "" }
                    .font(.callout).accessibilityIdentifier("keypad.clear")
            }
            .padding(.horizontal)
            ForEach(keys, id: \.self) { row in
                HStack(spacing: 10) {
                    ForEach(row, id: \.self) { key in keyButton(key) }
                }
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func keyButton(_ key: String) -> some View {
        Button {
            tapKey(key)
        } label: {
            Text(key)
                .scaledSystemFont(28, relativeTo: .title, weight: .semibold, design: .rounded)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(keyID(key))
        .accessibilityLabel(keyLabel(key))
    }

    private func keyID(_ key: String) -> String {
        switch key {
        case ".": return "keypad.dot"
        case "⌫": return "keypad.back"
        default:  return "keypad.k.\(key)"
        }
    }
    private func keyLabel(_ key: String) -> String {
        switch key {
        case ".": return "decimal point"
        case "⌫": return "delete"
        default:  return key
        }
    }

    private func tapKey(_ key: String) {
        switch key {
        case "⌫":
            if !entry.isEmpty { entry.removeLast() }
        case ".":
            if !entry.contains(".") { entry += entry.isEmpty ? "0." : "." }
        default:
            // Guard against absurd lengths / leading-zero pile-ups.
            if entry == "0" { entry = key } else if entry.count < 6 { entry += key }
        }
    }
}
