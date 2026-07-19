import SwiftUI
import CadenceCore
import CadenceFeatures

struct WatchIntervalSetupView: View {
    let kind: String
    @Bindable var model: IntervalSetupModel
    let onStart: (IntervalPlan) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        GeometryReader { geo in
            let compact = geo.size.height < 185
            let rowHeight: CGFloat = compact ? 24 : 28
            VStack(spacing: compact ? 3 : 5) {
                if !compact {
                    Text("\(kind) setup")
                        .font(.caption.bold())
                        .lineLimit(1)
                }

                setupRow("Warmup", value: $model.warmupSeconds, range: 0...600, step: 60, format: timeFormat, rowHeight: rowHeight)
                setupRow("Rounds", value: $model.rounds, range: 1...30, step: 1, format: { "\($0)" }, rowHeight: rowHeight)
                setupRow("Round", value: $model.workSeconds, range: 5...600, step: 60, format: timeFormat, rowHeight: rowHeight)
                setupRow("Rest", value: $model.restSeconds, range: 5...600, step: 30, format: timeFormat, rowHeight: rowHeight)
                setupRow("Cooldown", value: $model.cooldownSeconds, range: 0...600, step: 60, format: timeFormat, rowHeight: rowHeight)

                Button {
                    onStart(model.intervalPlan())
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
}
