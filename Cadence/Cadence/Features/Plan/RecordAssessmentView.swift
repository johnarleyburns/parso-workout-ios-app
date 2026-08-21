import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

/// Records one assessment result (strength-pivot P4). The form adapts to the
/// kind's unit: estimated-1RM tests take a lift + load × reps (and show the
/// computed e1RM live); rep-max tests take a lift + fixed load + reps; bodyweight
/// rep tests take a rep count; hold tests take a duration. Saving inserts an
/// `Assessment` the engine then tracks longitudinally.
struct RecordAssessmentView: View {
    let kind: AssessmentKind

    @Environment(\.modelContext) var context
    @Environment(\.dismiss) var dismiss
    @Environment(AppSettings.self) var settings

    @State var exerciseName = ""
    @State var picking = false
    @State var weightText = ""
    @State var reps = 10
    @State var minutes = 0
    @State var seconds = 30
    @State var notes = ""

    @State var distanceText = ""
    @State var timeMinutes = 0
    @State var timeSeconds = 0
    @State var endingHRText = ""
    @State var age = 30
    @State var sex = 1

    var weightEntry: Double { Double(weightText) ?? 0 }
    var weightKg: Double { WorkoutMath.canonical(weightEntry, from: settings.unit) }
    var distanceEntry: Double { Double(distanceText) ?? 0 }
    var endingHREntry: Double { Double(endingHRText) ?? 0 }
    var cardioTimeSeconds: Double { Double(timeMinutes * 60 + timeSeconds) }

    var estimated1RM: Double {
        AssessmentMath.e1RM(weight: weightKg, reps: reps, formula: settings.formula)
    }

    var computedVO2max: Double {
        switch kind {
        case .cooper12min:
            return CardioMath.cooperVO2max(distanceMeters: distanceEntry)
        case .run1_5mile:
            return CardioMath.run1_5mileVO2max(timeSeconds: cardioTimeSeconds)
        case .rockportWalk:
            return CardioMath.rockportVO2max(weightKg: weightKg, ageYears: age,
                                            sexCode: sex, walkTimeSeconds: cardioTimeSeconds,
                                            endingHR: endingHREntry)
        case .queensCollegeStep:
            return CardioMath.queensCollegeVO2max(recoveryHR: endingHREntry, sexCode: sex)
        default:
            return 0
        }
    }

    var canSave: Bool {
        switch kind {
        case .cooper12min:
            return distanceEntry > 0
        case .run1_5mile:
            return cardioTimeSeconds > 0
        case .rockportWalk:
            return weightEntry > 0 && cardioTimeSeconds > 0 && endingHREntry > 0
        case .queensCollegeStep:
            return endingHREntry > 0
        default:
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

    func save() {
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let lift = kind.concernsLift ? exerciseName : nil
        let value: Double
        let inputWeight: Double
        let inputReps: Int
        var savedDistance: Double?
        var savedTime: Double?
        var savedEndingHR: Double?
        var savedAge: Int?
        var savedSex: Int?

        switch kind {
        case .e1RM:
            value = estimated1RM
            inputWeight = weightKg
            inputReps = reps
        case .repMax:
            value = Double(reps)
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
        case .cooper12min:
            value = computedVO2max
            inputWeight = 0
            inputReps = 0
            savedDistance = distanceEntry
        case .run1_5mile:
            value = computedVO2max
            inputWeight = 0
            inputReps = 0
            savedTime = cardioTimeSeconds
        case .rockportWalk:
            value = computedVO2max
            inputWeight = weightKg
            inputReps = 0
            savedTime = cardioTimeSeconds
            savedEndingHR = endingHREntry
            savedAge = age
            savedSex = sex
        case .queensCollegeStep:
            value = computedVO2max
            inputWeight = 0
            inputReps = 0
            savedEndingHR = endingHREntry
            savedSex = sex
        case .vo2maxField, .wingate:
            value = weightEntry
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
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
            inputDistance: savedDistance,
            inputTime: savedTime,
            inputEndingHR: savedEndingHR,
            inputAge: savedAge,
            inputSex: savedSex)
        context.insert(assessment)
        try? context.save()
        Haptics.prAchieved()
        dismiss()
    }
}
