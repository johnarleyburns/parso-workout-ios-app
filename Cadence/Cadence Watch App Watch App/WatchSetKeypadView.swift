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

                if let hint = model.previousSetHint {
                    Text(hint).font(.caption).foregroundStyle(.secondary)
                }

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
                Button("\(String(format: "%.0f", increment.chips.first!))") {
                    model.currentWeight = max(increment.range.lowerBound, model.currentWeight + increment.chips.first!)
                }
                .buttonStyle(.bordered)
                Text(model.weightValue(model.currentWeight))
                    .font(.title2.monospaced())
                    .focusable()
                    .digitalCrownRotation(
                        $bindableModel.currentWeight,
                        from: increment.range.lowerBound,
                        through: increment.range.upperBound,
                        by: increment.crownDetent,
                        sensitivity: .medium, isContinuous: false
                    )
                Button("+\(String(format: "%.0f", increment.chips.last!))") {
                    model.currentWeight = min(increment.range.upperBound, model.currentWeight + increment.chips.last!)
                }
                .buttonStyle(.bordered)
            }
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
