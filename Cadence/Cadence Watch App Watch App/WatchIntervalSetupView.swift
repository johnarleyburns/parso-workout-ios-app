import SwiftUI
import CadenceCore
import CadenceFeatures

struct WatchIntervalSetupView: View {
    let kind: String
    @Bindable var model: IntervalSetupModel
    let onStart: (IntervalPlan) -> Void

    @Environment(\.dismiss) private var dismiss

    private var isHIIT: Bool { kind.lowercased() == "hiit" }
    private var isBoxing: Bool { kind.lowercased() == "boxing" }

    var body: some View {
        GeometryReader { geo in
            let compact = geo.size.height < 185
            VStack(spacing: compact ? 3 : 5) {
                if !compact {
                    Text(kind)
                        .font(.caption.bold())
                        .lineLimit(1)
                }

                if isHIIT {
                    hiitSetup(compact: compact)
                } else if isBoxing {
                    boxingSetup(compact: compact)
                } else {
                    genericSetup(compact: compact)
                }

                Button {
                    onStart(intervalPlan())
                    dismiss()
                } label: {
                    Label("Start", systemImage: "play.fill")
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity, minHeight: compact ? 28 : 32)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .accessibilityIdentifier("intervalSetup.start")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(.horizontal, 6)
            .padding(.vertical, compact ? 2 : 5)
        }
    }

    // MARK: - HIIT protocol picker

    private func hiitSetup(compact: Bool) -> some View {
        VStack(spacing: 4) {
            Text("Protocol")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Picker("Protocol", selection: $model.hiitProtocol) {
                ForEach(HIITProtocol.allCases, id: \.self) { proto in
                    Text(proto.displayName).tag(proto)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: compact ? 60 : 80)
        }
    }

    // MARK: - Boxing setup (rounds, round, rest)

    private func boxingSetup(compact: Bool) -> some View {
        VStack(spacing: compact ? 2 : 4) {
            boxingPickerRow("Rounds", value: $model.rounds, range: 1...20, step: 1, format: { "\($0)" }, compact: compact)
            boxingPickerRow("Round", value: $model.boxingRoundMinutes, range: 2...3, step: 1, format: { "\($0) min" }, compact: compact)
            boxingPickerRow("Rest", value: $model.boxingRestSeconds, range: 30...60, step: 30, format: { "\($0) sec" }, compact: compact)
        }
    }

    private func boxingPickerRow(_ label: String, value: Binding<Int>, range: ClosedRange<Int>, step: Int, format: @escaping (Int) -> String, compact: Bool) -> some View {
        let rowHeight: CGFloat = compact ? 24 : 28
        return HStack(spacing: 3) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(width: 40, alignment: .leading)

            stepButton(systemName: "minus.circle.fill", disabled: value.wrappedValue <= range.lowerBound) {
                value.wrappedValue = max(range.lowerBound, value.wrappedValue - step)
            }
            .accessibilityLabel("Decrease \(label)")

            Text(format(value.wrappedValue))
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: 56)

            stepButton(systemName: "plus.circle.fill", disabled: value.wrappedValue >= range.upperBound) {
                value.wrappedValue = min(range.upperBound, value.wrappedValue + step)
            }
            .accessibilityLabel("Increase \(label)")
        }
        .frame(height: rowHeight)
        .padding(.horizontal, 5)
        .background(.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Generic setup (warmup, rounds, work, rest, cooldown)

    private func genericSetup(compact: Bool) -> some View {
        let rowHeight: CGFloat = compact ? 24 : 28
        return VStack(spacing: compact ? 3 : 5) {
            setupRow("Warmup", value: $model.warmupSeconds, range: 0...600, step: 60, format: timeFormat, rowHeight: rowHeight)
            setupRow("Rounds", value: $model.rounds, range: 1...30, step: 1, format: { "\($0)" }, rowHeight: rowHeight)
            setupRow("Round", value: $model.workSeconds, range: 5...600, step: 60, format: timeFormat, rowHeight: rowHeight)
            setupRow("Rest", value: $model.restSeconds, range: 5...600, step: 30, format: timeFormat, rowHeight: rowHeight)
            setupRow("Cooldown", value: $model.cooldownSeconds, range: 0...600, step: 60, format: timeFormat, rowHeight: rowHeight)
        }
    }

    // MARK: - Helpers

    private func setupRow(_ label: String,
                          value: Binding<Int>,
                          range: ClosedRange<Int>,
                          step: Int,
                          format: @escaping (Int) -> String,
                          rowHeight: CGFloat) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(width: 54, alignment: .leading)

            stepButton(systemName: "minus.circle.fill", disabled: value.wrappedValue <= range.lowerBound) {
                value.wrappedValue = clamped(value.wrappedValue - step, range: range)
            }
            .accessibilityLabel("Decrease \(label)")

            Text(format(value.wrappedValue))
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: 48)

            stepButton(systemName: "plus.circle.fill", disabled: value.wrappedValue >= range.upperBound) {
                value.wrappedValue = clamped(value.wrappedValue + step, range: range)
            }
            .accessibilityLabel("Increase \(label)")
        }
        .frame(height: rowHeight)
        .padding(.horizontal, 5)
        .background(.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func stepButton(systemName: String,
                            disabled: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 26, height: 24)
        }
        .buttonStyle(.plain)
        .foregroundStyle(disabled ? Color.secondary.opacity(0.45) : Color.primary)
        .disabled(disabled)
    }

    private func clamped(_ value: Int, range: ClosedRange<Int>) -> Int {
        max(range.lowerBound, min(range.upperBound, value))
    }

    private func timeFormat(_ s: Int) -> String {
        String(format: "%d:%02d", s / 60, s % 60)
    }

    private func intervalPlan() -> IntervalPlan {
        if isHIIT {
            return model.hiitIntervalPlan()
        } else if isBoxing {
            return model.boxingIntervalPlan()
        } else {
            return model.intervalPlan()
        }
    }
}
