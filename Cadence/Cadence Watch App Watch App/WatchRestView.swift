import SwiftUI
import CadenceCore
import CadenceFeatures

struct WatchRestView: View {
    let model: WatchStrengthFlowModel

    @State private var timer: Timer?

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Text("REST").font(.caption.bold()).foregroundStyle(.secondary)
            Text(formatTime(TimeInterval(model.restTimer.remaining)))
                .font(.system(size: 52, weight: .heavy, design: .monospaced))

            if model.restTimer.isRunning {
                ProgressView(value: model.restTimer.progress)
                    .tint(.green)
                    .padding(.horizontal, 20)
            }

            HStack(spacing: 12) {
                Button("+30s") { model.addRestTime(30) }.buttonStyle(.bordered)
                Button("Next Set") {
                    timer?.invalidate()
                    model.finishRest()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("watchRest.nextSet")
            }
            Spacer()
        }
        .onAppear {
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                model.restTimer.tick()
            }
        }
        .onDisappear { timer?.invalidate() }
    }

    private func formatTime(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
