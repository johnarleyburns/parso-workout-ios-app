import SwiftUI
import CadenceCore
import CadenceFeatures

/// Optional warm-up countdown shown before the first set of a strength workout.
/// Skip (or the timer reaching zero) moves on to the first set.
struct WatchWarmUpView: View {
    let model: WatchStrengthFlowModel
    @State private var ticker: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color.orange.ignoresSafeArea(.all)

            VStack(spacing: 8) {
                Spacer()
                Text("WARM-UP").font(.caption2.bold()).foregroundStyle(.white.opacity(0.8))
                Text(formatTime(model.warmupTimerModel.remaining))
                    .font(.system(size: 52, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.white)
                    .accessibilityLabel("Warm-up time remaining")
                HStack(spacing: 16) {
                    Button("+1m") {
                        WatchHaptics.tap()
                        model.warmupTimerModel.add(60)
                    }
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("watchWarmup.add")
                    Button("Skip") {
                        WatchHaptics.success()
                        model.endWarmup()
                    }
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("watchWarmup.skip")
                }
                .padding(.top, 8)
                Spacer()
            }
        }
        .onAppear {
            ticker?.cancel()
            ticker = Task { @MainActor in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    if Task.isCancelled { break }
                    model.warmupTimerModel.tick()
                    if model.warmupTimerModel.remaining <= 0 {
                        WatchHaptics.success()
                        model.endWarmup()
                        break
                    }
                }
            }
        }
        .onDisappear { ticker?.cancel() }
    }

    private func formatTime(_ seconds: Int) -> String {
        let total = max(0, seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
