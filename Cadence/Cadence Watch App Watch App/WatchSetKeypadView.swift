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

                setHistorySection(title: "This Workout", lines: model.currentWorkoutHistoryLines)
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

                Text("crown \(String(format: "%.1f", increment.crownDetent)) \(model.unit.abbreviation)")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .padding()
        }
    }

    private var weightControl: some View {
        VStack(spacing: 4) {
            Text("Weight (\(model.unit.abbreviation))")
                .font(.caption.bold()).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Button(shortChipLabel(increment.chips.first!)) {
                    adjustWeight(by: increment.chips.first!)
                }
                .buttonStyle(.bordered)
                Text(model.currentWeightText)
                    .font(.title3.monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(minWidth: 54)
                    .focusable()
                    .digitalCrownRotation(
                        $bindableModel.currentWeightDisplay,
                        from: increment.range.lowerBound,
                        through: increment.range.upperBound,
                        by: increment.crownDetent,
                        sensitivity: .medium, isContinuous: false
                    )
                Button(shortChipLabel(increment.chips.last!)) {
                    adjustWeight(by: increment.chips.last!)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    /// Steps the weight by a chip amount, in the user's display unit, clamped to
    /// the valid range. Operating in display units keeps every value on a 2.5
    /// boundary (never an odd "44 lb") and makes "+2.5" add exactly 2.5 lb.
    private func adjustWeight(by delta: Double) {
        let next = model.currentWeightDisplay + delta
        model.currentWeightDisplay = min(increment.range.upperBound,
                                         max(increment.range.lowerBound, next))
    }

    private func shortChipLabel(_ value: Double) -> String {
        value < 0 ? "-" : "+"
    }

    @ViewBuilder
    private func setHistorySection(title: String, lines: [WatchSetHistoryLine]) -> some View {
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
                        Spacer(minLength: 0)
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
                Button("-1") { model.currentReps = max(1, model.currentReps - 1) }.buttonStyle(.bordered)
                Text("\(Int(model.currentReps))")
                    .font(.title2.monospaced())
                    .focusable()
                    .digitalCrownRotation($bindableModel.currentReps, from: 1, through: 30, by: 1,
                                          sensitivity: .medium, isContinuous: false)
                Button("+1") { model.currentReps += 1 }.buttonStyle(.bordered)
            }
        }
    }

    private func sendSync() {
        guard let payload = model.lastSyncPayload else { return }
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        WCSession.default.transferUserInfo(payload)
    }
}
