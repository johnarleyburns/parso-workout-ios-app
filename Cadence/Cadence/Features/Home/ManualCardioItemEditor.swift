import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

// MARK: - Cardio item editor

enum ManualCardioKind: String, CaseIterable, Identifiable {
    case steadyState = "Steady state"
    case intervals = "Intervals"
    case open = "Open activity"

    var id: String { rawValue }
}

enum ManualCardioActivity: String, CaseIterable, Identifiable {
    case walk = "Walk"
    case run = "Run"
    case bike = "Bike"
    case row = "Row"
    case swim = "Swim"
    case elliptical = "Elliptical"
    case stairs = "Stairs"
    case other = "Other"

    var id: String { rawValue }

    init(activity: CardioActivity) {
        switch activity {
        case .walk: self = .walk
        case .run: self = .run
        case .bike: self = .bike
        case .row: self = .row
        case .swim: self = .swim
        case .elliptical: self = .elliptical
        case .stairs: self = .stairs
        case .other: self = .other
        }
    }

    func value(otherName: String) -> CardioActivity {
        switch self {
        case .walk: return .walk
        case .run: return .run
        case .bike: return .bike
        case .row: return .row
        case .swim: return .swim
        case .elliptical: return .elliptical
        case .stairs: return .stairs
        case .other: return .other(otherName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                   ? "Other"
                                   : otherName.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}

enum ManualIntensityMode: String, CaseIterable, Identifiable {
    case heartRateZone = "Heart-rate zone"
    case rpe = "RPE"
    case talkTest = "Talk test"

    var id: String { rawValue }
}

struct ManualCardioItemEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var item: CardioItem
    @State private var kind: ManualCardioKind
    @State private var activity: ManualCardioActivity
    @State private var otherActivity: String
    @State private var instructions: String

    @State private var durationText: String
    @State private var distanceText: String
    @State private var intensityMode: ManualIntensityMode
    @State private var intensityText: String
    @State private var targetZoneEnabled: Bool

    @State private var roundsText: String
    @State private var workSecondsText: String
    @State private var recoverySecondsText: String
    @State private var recoveryMode: ManualIntensityMode
    @State private var recoveryIntensityText: String
    @State private var goalText: String

    let onSave: (WorkoutItem) -> Void

    init(item: CardioItem, onSave: @escaping (WorkoutItem) -> Void) {
        self._item = State(initialValue: item)
        self.onSave = onSave

        var initialKind = ManualCardioKind.steadyState
        var initialActivity = CardioActivity.run
        var initialDuration = ""
        var initialDistance = ""
        var initialMode = ManualIntensityMode.heartRateZone
        var initialIntensity = "2"
        var initialTargetEnabled = false
        var initialRounds = "4"
        var initialWorkSeconds = "60"
        var initialRecoverySeconds = "120"
        var initialRecoveryMode = ManualIntensityMode.heartRateZone
        var initialRecoveryIntensity = "1"
        var initialGoal = ""

        switch item.prescription {
        case let .steadyState(value):
            initialKind = .steadyState
            initialActivity = value.activity
            initialDuration = value.durationSeconds.map { String(max(1, $0 / 60)) } ?? ""
            initialDistance = value.distanceMeters.map { String($0) } ?? ""
            initialMode = manualIntensityMode(for: value.intensity)
            initialIntensity = manualIntensityValue(for: value.intensity)
            initialTargetEnabled = value.intensity != nil
        case let .intervals(value):
            initialKind = .intervals
            initialActivity = value.activity
            initialMode = manualIntensityMode(for: value.work.intensity)
            initialIntensity = manualIntensityValue(for: value.work.intensity)
            initialTargetEnabled = true
            initialRounds = String(value.rounds)
            initialWorkSeconds = value.work.durationSeconds.map { String($0) } ?? "60"
            initialRecoverySeconds = value.recovery.durationSeconds.map { String($0) } ?? "120"
            initialRecoveryMode = manualIntensityMode(for: value.recovery.intensity)
            initialRecoveryIntensity = manualIntensityValue(for: value.recovery.intensity)
        case let .open(value):
            initialKind = .open
            initialActivity = value.activity
            initialMode = manualIntensityMode(for: value.targetIntensity)
            initialIntensity = manualIntensityValue(for: value.targetIntensity)
            initialTargetEnabled = value.targetIntensity != nil
            initialGoal = value.goalText
        }

        self._kind = State(initialValue: initialKind)
        self._activity = State(initialValue: ManualCardioActivity(activity: initialActivity))
        if case let .other(name) = initialActivity {
            self._otherActivity = State(initialValue: name)
        } else {
            self._otherActivity = State(initialValue: "")
        }
        self._durationText = State(initialValue: initialDuration)
        self._distanceText = State(initialValue: initialDistance)
        self._intensityMode = State(initialValue: initialMode)
        self._intensityText = State(initialValue: initialIntensity)
        self._targetZoneEnabled = State(initialValue: initialTargetEnabled)
        self._roundsText = State(initialValue: initialRounds)
        self._workSecondsText = State(initialValue: initialWorkSeconds)
        self._recoverySecondsText = State(initialValue: initialRecoverySeconds)
        self._recoveryMode = State(initialValue: initialRecoveryMode)
        self._recoveryIntensityText = State(initialValue: initialRecoveryIntensity)
        self._goalText = State(initialValue: initialGoal)
        self._instructions = State(initialValue: item.instructions ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Cardio") {
                    Picker("Format", selection: $kind) {
                        ForEach(ManualCardioKind.allCases) { value in
                            Text(value.rawValue).tag(value)
                        }
                    }
                    Picker("Activity", selection: $activity) {
                        ForEach(ManualCardioActivity.allCases) { value in
                            Text(value.rawValue).tag(value)
                        }
                    }
                    if activity == .other {
                        TextField("Activity name", text: $otherActivity)
                    }
                }

                switch kind {
                case .steadyState:
                    steadyStateFields
                case .intervals:
                    intervalFields
                case .open:
                    openFields
                }

                Section("Instructions") {
                    TextField("Optional coaching cue", text: $instructions,
                              axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .navigationTitle("Cardio item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("manualCardio.save")
                }
            }
        }
    }

    private var steadyStateFields: some View {
        Section("Steady state") {
            TextField("Duration (minutes)", text: $durationText)
                .keyboardType(.numberPad)
            TextField("Distance (meters, optional)", text: $distanceText)
                .keyboardType(.decimalPad)
            Toggle("Set a target intensity", isOn: $targetZoneEnabled)
            if targetZoneEnabled {
                intensityFields(mode: $intensityMode, value: $intensityText)
            }
        }
    }

    private var intervalFields: some View {
        Section("Intervals") {
            TextField("Rounds", text: $roundsText)
                .keyboardType(.numberPad)
            TextField("Work seconds", text: $workSecondsText)
                .keyboardType(.numberPad)
            intensityFields(mode: $intensityMode, value: $intensityText,
                            title: "Work intensity")
            TextField("Recovery seconds", text: $recoverySecondsText)
                .keyboardType(.numberPad)
            intensityFields(mode: $recoveryMode, value: $recoveryIntensityText,
                            title: "Recovery intensity")
        }
    }

    private var openFields: some View {
        Section("Open activity") {
            TextField("Goal", text: $goalText, axis: .vertical)
                .lineLimit(2...4)
            Toggle("Set a target intensity", isOn: $targetZoneEnabled)
            if targetZoneEnabled {
                intensityFields(mode: $intensityMode, value: $intensityText)
            }
        }
    }

    @ViewBuilder
    private func intensityFields(mode: Binding<ManualIntensityMode>,
                                 value: Binding<String>,
                                 title: String = "Intensity") -> some View {
        Picker(title, selection: mode) {
            ForEach(ManualIntensityMode.allCases) { option in
                Text(option.rawValue).tag(option)
            }
        }
        TextField(mode.wrappedValue == .heartRateZone ? "Zone (1–5)" : "Value",
                  text: value)
            .keyboardType(.decimalPad)
    }

    private func save() {
        let selectedActivity = activity.value(otherName: otherActivity)
        let prescription: CardioPrescription
        switch kind {
        case .steadyState:
            let intensity = targetZoneEnabled
                ? makeIntensity(mode: intensityMode, text: intensityText)
                : nil
            prescription = .steadyState(SteadyState(
                activity: selectedActivity,
                durationSeconds: minutes(durationText),
                distanceMeters: positiveDouble(distanceText),
                intensity: intensity))
        case .intervals:
            let work = IntervalSegment(
                durationSeconds: positiveInt(workSecondsText) ?? 60,
                intensity: makeIntensity(mode: intensityMode, text: intensityText))
            let recovery = IntervalSegment(
                durationSeconds: positiveInt(recoverySecondsText) ?? 120,
                intensity: makeIntensity(mode: recoveryMode,
                                         text: recoveryIntensityText))
            prescription = .intervals(Intervals(
                activity: selectedActivity,
                rounds: max(1, positiveInt(roundsText) ?? 4),
                work: work,
                recovery: recovery))
        case .open:
            let target = targetZoneEnabled
                ? makeIntensity(mode: intensityMode, text: intensityText)
                : nil
            prescription = .open(OpenActivity(
                activity: selectedActivity,
                goalText: goalText.trimmingCharacters(in: .whitespacesAndNewlines),
                targetIntensity: target))
        }
        item.prescription = prescription
        item.instructions = instructions.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        onSave(.cardio(item))
    }

    private func makeIntensity(mode: ManualIntensityMode, text: String) -> CardioIntensity {
        switch mode {
        case .heartRateZone:
            return .heartRateZone(min(5, max(1, Int(text) ?? 2)))
        case .rpe:
            let value = min(10, max(0, Double(text) ?? 5))
            return .rpe(value...value)
        case .talkTest:
            return .talkTest(.shortPhrases)
        }
    }

    private func minutes(_ text: String) -> Int? {
        guard let value = positiveInt(text) else { return nil }
        return value * 60
    }

    private func positiveInt(_ text: String) -> Int? {
        guard let value = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)), value > 0 else {
            return nil
        }
        return value
    }

    private func positiveDouble(_ text: String) -> Double? {
        guard let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)), value > 0 else {
            return nil
        }
        return value
    }

}
