import SwiftUI
import SwiftData
import CadenceCore

/// Records one assessment result (strength-pivot P4). The form adapts to the
/// kind's unit: estimated-1RM tests take a lift + load × reps (and show the
/// computed e1RM live); rep-max tests take a lift + fixed load + reps; bodyweight
/// rep tests take a rep count; hold tests take a duration. Saving inserts an
/// `Assessment` the engine then tracks longitudinally.
struct RecordAssessmentView: View {
    let kind: AssessmentKind

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings

    @State private var exerciseName = ""
    @State private var picking = false
    @State private var weightText = ""      // in the user's display unit
    @State private var reps = 10
    @State private var minutes = 0
    @State private var seconds = 30
    @State private var notes = ""

    private var weightEntry: Double { Double(weightText) ?? 0 }
    private var weightKg: Double { WorkoutMath.canonical(weightEntry, from: settings.unit) }

    /// Live estimated 1RM (kg) for the e1RM test, from the entered load × reps.
    private var estimated1RM: Double {
        AssessmentMath.e1RM(weight: weightKg, reps: reps, formula: settings.formula)
    }

    private var canSave: Bool {
        switch kind.unit {
        case .weightKg: return !exerciseName.isEmpty && weightEntry > 0 && reps > 0
        case .reps:
            if kind.concernsLift { return !exerciseName.isEmpty && weightEntry > 0 && reps > 0 }
            return reps > 0
        case .seconds: return (minutes * 60 + seconds) > 0
        case .mlKgMin: return weightEntry > 0
        case .watts: return weightEntry > 0
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(kind.protocolText)
                        .font(.footnote).foregroundStyle(.secondary)
                }

                if kind.concernsLift {
                    liftSection
                }

                inputSection

                Section("Notes") {
                    TextField("Optional", text: $notes, axis: .vertical)
                        .accessibilityIdentifier("record.assessment.notes")
                }
            }
            .navigationTitle(kind.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("record.assessment.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                        .accessibilityIdentifier("record.assessment.save")
                }
            }
            .sheet(isPresented: $picking) {
                ExercisePickerView { exerciseName = $0.name }
            }
        }
    }

    // MARK: Sections

    private var liftSection: some View {
        Section("Lift") {
            Button {
                picking = true
            } label: {
                HStack {
                    Text(exerciseName.isEmpty ? "Choose a lift" : exerciseName)
                        .foregroundStyle(exerciseName.isEmpty ? .secondary : .primary)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
            }
            .accessibilityIdentifier("record.assessment.lift")
        }
    }

    @ViewBuilder
    private var inputSection: some View {
        switch kind.unit {
        case .weightKg:
            Section("Top set") {
                weightField
                repsStepper
                HStack {
                    Text("Estimated 1RM")
                    Spacer()
                    Text(Format.weight(estimated1RM, unit: settings.unit, decimals: 0))
                        .font(.body.weight(.semibold)).monospacedDigit()
                        .accessibilityIdentifier("record.assessment.e1rm")
                }
                .foregroundStyle(.secondary)
            }
        case .reps:
            if kind.concernsLift {
                Section("Test set") {
                    weightField
                    repsStepper
                }
            } else {
                Section("Result") { repsStepper }
            }
        case .seconds:
            Section("Hold time") { durationPicker }
        case .mlKgMin:
            Section("Result") {
                HStack {
                    Text("VO₂max (mL/kg/min)")
                    Spacer()
                    TextField("0", text: $weightText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 120)
                        .accessibilityIdentifier("record.assessment.vo2max")
                }
            }
        case .watts:
            Section("Result") {
                HStack {
                    Text("Peak power (W)")
                    Spacer()
                    TextField("0", text: $weightText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 120)
                        .accessibilityIdentifier("record.assessment.watts")
                }
            }
        }
    }

    private var weightField: some View {
        HStack {
            Text("Load (\(settings.unit.abbreviation))")
            Spacer()
            TextField("0", text: $weightText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 120)
                .accessibilityIdentifier("record.assessment.weight")
        }
    }

    private var repsStepper: some View {
        Stepper(value: $reps, in: 1...200) {
            HStack {
                Text("Reps")
                Spacer()
                Text("\(reps)").monospacedDigit().foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("record.assessment.reps")
    }

    private var durationPicker: some View {
        HStack(spacing: 0) {
            Picker("Minutes", selection: $minutes) {
                ForEach(0...20, id: \.self) { Text("\($0) min").tag($0) }
            }
            .pickerStyle(.wheel)
            .accessibilityIdentifier("record.assessment.minutes")
            Picker("Seconds", selection: $seconds) {
                ForEach(0...59, id: \.self) { Text("\($0) s").tag($0) }
            }
            .pickerStyle(.wheel)
            .accessibilityIdentifier("record.assessment.seconds")
        }
        .frame(height: 130)
    }

    // MARK: Save

    private func save() {
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let lift = kind.concernsLift ? exerciseName : nil
        let value: Double
        let inputWeight: Double
        let inputReps: Int

        switch kind {
        case .e1RM:
            value = estimated1RM
            inputWeight = weightKg
            inputReps = reps
        case .repMax:
            value = Double(reps)         // result = reps achieved at the fixed load
            inputWeight = weightKg
            inputReps = reps
        case .pushupMax, .pullupMax, .bodyweightSquatMax:
            value = Double(reps)
            inputWeight = 0
            inputReps = reps
        case .plankHold, .hollowHold:
            value = Double(minutes * 60 + seconds)
            inputWeight = 0
            inputReps = 0
        case .vo2maxField, .wingate:
            value = weightEntry          // raw numeric entry (mL/kg/min or watts)
            inputWeight = 0
            inputReps = 0
        }

        let assessment = Assessment(
            date: Date(),
            kind: kind,
            value: value,
            inputWeight: inputWeight,
            inputReps: inputReps,
            exerciseName: lift,
            protocolName: kind.displayName,
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes)
        context.insert(assessment)
        try? context.save()
        Haptics.prAchieved()
        dismiss()
    }
}
