import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

extension RecordAssessmentView {
    var liftSection: some View {
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
    var inputSection: some View {
        switch kind {
        case .cooper12min:
            cooperInputSection
        case .run1_5mile:
            runTimeInputSection
        case .rockportWalk:
            rockportInputSection
        case .queensCollegeStep:
            queensCollegeInputSection
        default:
            defaultInputSection
        }
    }

    @ViewBuilder
    var defaultInputSection: some View {
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
                    Text("VO\u{2082}max (mL/kg/min)")
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

    var cooperInputSection: some View {
        Section("Distance") {
            HStack {
                Text("Distance (meters)")
                Spacer()
                TextField("0", text: $distanceText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 120)
                    .accessibilityIdentifier("record.assessment.distance")
            }
            if distanceEntry > 0 {
                vo2maxPreviewRow
            }
        }
    }

    var runTimeInputSection: some View {
        Section("Run time") {
            cardioTimePicker
            if cardioTimeSeconds > 0 {
                vo2maxPreviewRow
            }
        }
    }

    var rockportInputSection: some View {
        Group {
            Section("Walk time & heart rate") {
                cardioTimePicker
                HStack {
                    Text("Ending HR (bpm)")
                    Spacer()
                    TextField("0", text: $endingHRText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 120)
                        .accessibilityIdentifier("record.assessment.endingHR")
                }
            }
            Section("About you") {
                weightField
                Stepper(value: $age, in: 10...99) {
                    HStack {
                        Text("Age")
                        Spacer()
                        Text("\(age)").monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("record.assessment.age")
                Picker("Sex", selection: $sex) {
                    Text("Male").tag(1)
                    Text("Female").tag(0)
                }
                .accessibilityIdentifier("record.assessment.sex")
            }
            if weightEntry > 0 && cardioTimeSeconds > 0 && endingHREntry > 0 {
                Section { vo2maxPreviewRow }
            }
        }
    }

    var queensCollegeInputSection: some View {
        Section("Recovery heart rate") {
            HStack {
                Text("Recovery HR (bpm)")
                Spacer()
                TextField("0", text: $endingHRText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 120)
                    .accessibilityIdentifier("record.assessment.recoveryHR")
            }
            Picker("Sex", selection: $sex) {
                Text("Male").tag(1)
                Text("Female").tag(0)
            }
            .accessibilityIdentifier("record.assessment.sex")
            if endingHREntry > 0 {
                vo2maxPreviewRow
            }
        }
    }

    var vo2maxPreviewRow: some View {
        HStack {
            Text("Estimated VO\u{2082}max")
            Spacer()
            Text(String(format: "%.1f mL/kg/min", computedVO2max))
                .font(.body.weight(.semibold)).monospacedDigit()
                .accessibilityIdentifier("record.assessment.computedVO2max")
        }
        .foregroundStyle(.secondary)
    }

    var cardioTimePicker: some View {
        HStack(spacing: 0) {
            Picker("Minutes", selection: $timeMinutes) {
                ForEach(0...60, id: \.self) { Text("\($0) min").tag($0) }
            }
            .pickerStyle(.wheel)
            .accessibilityIdentifier("record.assessment.timeMinutes")
            Picker("Seconds", selection: $timeSeconds) {
                ForEach(0...59, id: \.self) { Text("\($0) s").tag($0) }
            }
            .pickerStyle(.wheel)
            .accessibilityIdentifier("record.assessment.timeSeconds")
        }
        .frame(height: 130)
    }

    var weightField: some View {
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

    var repsStepper: some View {
        Stepper(value: $reps, in: 1...200) {
            HStack {
                Text("Reps")
                Spacer()
                Text("\(reps)").monospacedDigit().foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("record.assessment.reps")
    }

    var durationPicker: some View {
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

}
