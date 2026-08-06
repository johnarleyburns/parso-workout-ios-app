import SwiftUI
import WatchConnectivity
import CadenceCore
import CadenceFeatures

struct WatchSetKeypadView: View {
    @Bindable var bindableModel: WatchStrengthFlowModel
    var model: WatchStrengthFlowModel { bindableModel }

    init(model: WatchStrengthFlowModel) {
        self.bindableModel = model
    }

    private var exercise: Exercise? {
        if case .keypad(let ex) = model.stage { return ex }
        return nil
    }

    private var increment: WeightIncrement {
        WeightIncrement(unit: model.unit)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if let ex = exercise {
                    Text(ex.name).font(.headline)
                }

                Text("Set \(model.currentWorkingSetIndex)")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                if let hint = model.previousSetHint {
                    Text(hint).font(.caption).foregroundStyle(.secondary)
                }

                setHistorySection(title: "This Workout", lines: model.currentWorkoutHistoryLines, allowsDelete: true)
                setHistorySection(title: "Last Time", lines: model.previousWorkoutHistoryLines)

                if let performer = model.performerLabel {
                    HStack(spacing: 4) {
                        Text(String(performer.prefix(1)))
                            .font(.caption2.bold())
                            .frame(width: 18, height: 18)
                            .background(.blue)
                            .clipShape(Circle())
                            .foregroundStyle(.white)
                        Text(performer).font(.caption.bold())
                    }
                    .accessibilityLabel("Performer: \(performer)")
                }

                weightControl
                repsControl
                effortControl

                Button(action: { model.toggleWarmup() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                        Text("Warm-up").font(.caption.bold())
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(model.isWarmupSet ? Color.orange.opacity(0.3) : Color.white.opacity(0.1))
                    .clipShape(Capsule())
                    .foregroundStyle(model.isWarmupSet ? .orange : .secondary)
                }
                .accessibilityLabel(model.isWarmupSet ? "Warm-up on" : "Warm-up off")

                Button {
                    WatchHaptics.success()
                    if let _ = model.logSet() {
                        sendSync()
                    }
                } label: {
                    Label("Log Set", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .accessibilityIdentifier("logSetButton")

                Button {
                    WatchHaptics.success()
                    if let _ = model.logLastSet() {
                        sendSync()
                    }
                } label: {
                    Label("Last Set", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .accessibilityIdentifier("lastSetButton")

                if let ex = exercise {
                    Button(role: .destructive) {
                        WatchHaptics.delete()
                        if model.deleteExercise(ex) != nil {
                            sendSync()
                        }
                    } label: {
                        Label("Delete Exercise", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("watchSet.deleteExercise")
                }
            }
            .padding()
        }
    }

    private var weightControl: some View {
        VStack(spacing: 4) {
            Text("Weight (\(model.unit.abbreviation))")
                .font(.caption.bold()).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                weightChipColumn(increment.negativeChips)
                Text(model.currentWeightText)
                    .font(.title3.monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: 54)
                    .focusable()
                    .digitalCrownRotation(
                        $bindableModel.currentWeightDisplay,
                        from: increment.range.lowerBound,
                        through: increment.range.upperBound,
                        by: increment.crownDetent,
                        sensitivity: .medium, isContinuous: false
                    )
                weightChipColumn(increment.positiveChips)
            }
        }
    }

    private func weightChipColumn(_ chips: [Double]) -> some View {
        VStack(spacing: 3) {
            ForEach(chips, id: \.self) { chip in
                Button(chipSymbol(chip)) {
                    adjustWeight(by: chip)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .frame(width: 42)
                .accessibilityLabel("\(increment.chipLabel(chip)) \(model.unit.abbreviation)")
                .accessibilityIdentifier("watchWeight.\(chipIdentifier(chip))")
            }
        }
    }

    /// Steps the weight by a chip amount, in the user's display unit, clamped to
    /// the valid range. Operating in display units keeps every value on a 2.5
    /// boundary (never an odd "44 lb") and makes "+2.5" add exactly 2.5 lb.
    private func adjustWeight(by delta: Double) {
        WatchHaptics.tap()
        let next = model.currentWeightDisplay + delta
        model.currentWeightDisplay = min(increment.range.upperBound,
                                         max(increment.range.lowerBound, next))
    }

    private func chipSymbol(_ value: Double) -> String {
        switch abs(value) {
        case 10: return value < 0 ? "---" : "+++"
        case 5: return value < 0 ? "--" : "++"
        default: return value < 0 ? "-" : "+"
        }
    }

    private func chipIdentifier(_ value: Double) -> String {
        increment.chipLabel(value)
            .replacingOccurrences(of: "+", with: "plus")
            .replacingOccurrences(of: "-", with: "minus")
            .replacingOccurrences(of: ".", with: "_")
    }

    @ViewBuilder
    private func setHistorySection(title: String, lines: [WatchSetHistoryLine], allowsDelete: Bool = false) -> some View {
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text(title.uppercased())
                    .font(.caption2.bold())
                    .foregroundStyle(.tertiary)
                ForEach(lines) { line in
                    HStack(spacing: 5) {
                        Text(line.label)
                            .font(.caption2.bold())
                            .frame(width: 18, height: 18)
                            .background(line.isWarmup ? Color.orange.opacity(0.22) : Color.white.opacity(0.12), in: Circle())
                            .foregroundStyle(line.isWarmup ? .orange : .primary)
                        Text(line.weightText)
                            .monospacedDigit()
                            .lineLimit(1)
                        Text("x\(line.reps)")
                            .monospacedDigit()
                        if let rpe = line.rpe, !line.isWarmup {
                            Text("RPE \(Int(rpe.rounded()))")
                                .monospacedDigit()
                        }
                        Spacer(minLength: 0)
                        if allowsDelete, let setID = line.setID {
                            Button(role: .destructive) {
                                WatchHaptics.delete()
                                if model.deleteSet(id: setID) != nil {
                                    sendSync()
                                }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("watchSet.delete.\(line.label)")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private var repsControl: some View {
        VStack(spacing: 4) {
            Text("Reps").font(.caption.bold()).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Button("-1") {
                    WatchHaptics.tap()
                    model.currentReps = max(1, model.currentReps - 1)
                }
                .buttonStyle(.bordered)
                Text("\(Int(model.currentReps))")
                    .font(.title2.monospaced())
                    .focusable()
                    .digitalCrownRotation($bindableModel.currentReps, from: 1, through: 30, by: 1,
                                          sensitivity: .medium, isContinuous: false)
                Button("+1") {
                    WatchHaptics.tap()
                    model.currentReps += 1
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var effortControl: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                ForEach(WatchEffortMode.allCases) { mode in
                    Button(mode.displayName) {
                        WatchHaptics.tap()
                        model.effortMode = mode
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .tint(model.effortMode == mode ? .green : nil)
                }
            }
            .accessibilityIdentifier("watchEffort.mode")

            Picker(model.effortMode.displayName, selection: effortSelection) {
                Text("None").tag(0.0)
                ForEach(1...10, id: \.self) { value in
                    Text("\(value)").tag(Double(value))
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 58)
            .clipped()
            .accessibilityIdentifier("watchEffort.value")
        }
    }

    private var effortSelection: Binding<Double> {
        Binding(
            get: { model.effortValue ?? 0 },
            set: { model.effortValue = $0 <= 0 ? nil : $0 }
        )
    }

    private func sendSync() {
        guard let payload = model.lastSyncPayload else { return }
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        WCSession.default.transferUserInfo(payload)
    }
}
