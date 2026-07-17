import SwiftUI
import CadenceCore
import CadenceFeatures

struct WatchIntervalSetupView: View {
    let kind: String
    @Bindable var model: IntervalSetupModel
    let onStart: (IntervalPlan) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 10) {
            Text("\(kind) setup").font(.headline)

            field("Rounds", value: $model.rounds, range: 1...30)
            field("Work", value: $model.workSeconds, format: timeFormat, range: 5...600)
            field("Rest", value: $model.restSeconds, format: timeFormat, range: 5...600)

            Button("Start \(kind.lowercased())") {
                onStart(model.intervalPlan())
                dismiss()
            }
            .buttonStyle(.borderedProminent).tint(.green)

            Text("crown adjusts selected field")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding()
    }

    private func field(_ label: String, value: Binding<Int>, range _: ClosedRange<Int>) -> some View {
        let doubleBinding = Binding<Double>(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = Int($0) })
        return HStack {
            Text(label).font(.caption.bold()).foregroundStyle(.secondary)
            Spacer()
            Text("\(value.wrappedValue)")
                .font(.title3.monospacedDigit())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .focusable()
        .digitalCrownRotation(doubleBinding, from: 1, through: 600, by: 1, sensitivity: .medium, isContinuous: false)
    }

    private func field(_ label: String, value: Binding<Int>, format: @escaping (Int) -> String, range _: ClosedRange<Int>) -> some View {
        let doubleBinding = Binding<Double>(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = Int($0) })
        return HStack {
            Text(label).font(.caption.bold()).foregroundStyle(.secondary)
            Spacer()
            Text(format(value.wrappedValue))
                .font(.title3.monospacedDigit())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .focusable()
        .digitalCrownRotation(doubleBinding, from: 5, through: 600, by: 5, sensitivity: .medium, isContinuous: false)
    }

    private func timeFormat(_ s: Int) -> String {
        String(format: "%d:%02d", s / 60, s % 60)
    }
}
