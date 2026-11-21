import SwiftUI
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures

/// Optional warm-up countdown shown before the first set of a strength workout.
/// Skip (or the timer reaching zero) moves on to the first set.
struct WatchWarmUpView: View {
    let model: WatchStrengthFlowModel
    @Environment(WatchWorkoutManager.self) private var watchManager
    @State private var ticker: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color.orange.ignoresSafeArea(.all)

            VStack(spacing: 8) {
                // `minLength` (not a plain Spacer) guarantees this never
                // shrinks to zero and lets the caption sit under the system
                // clock/status area at the top of the screen.
                Spacer(minLength: 20)
                Text("WARM-UP").font(.caption2.bold()).foregroundStyle(.white.opacity(0.8))
                Text(formatTime(model.warmupTimerModel.remaining))
                    .font(.system(size: 52, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.white)
                    .accessibilityLabel("Warm-up time remaining")
                WatchLiveHeartRateBadge(bpm: watchManager.currentBPM)
                VStack(spacing: 6) {
                    Button("+1 min") {
                        WatchHaptics.tap()
                        model.warmupTimerModel.add(60)
                    }
                    .buttonStyle(WatchPillStyle(kind: .secondary, small: true))
                    .accessibilityIdentifier("watchWarmup.add")

                    Button("+5 min") {
                        WatchHaptics.tap()
                        model.warmupTimerModel.add(300)
                    }
                    .buttonStyle(WatchPillStyle(kind: .secondary, small: true))
                    .accessibilityIdentifier("watchWarmup.addFiveMinutes")

                    // Same two-action grammar as the workout: Pause/Resume on
                    // the left, Skip (finish the phase) on the right.
                    HStack(spacing: 6) {
                        Button(model.warmupTimerModel.isPaused ? "Resume" : "Pause") {
                            WatchHaptics.tap()
                            if model.warmupTimerModel.isPaused {
                                model.warmupTimerModel.resume()
                            } else {
                                model.warmupTimerModel.pause()
                            }
                        }
                        .buttonStyle(WatchPillStyle(kind: .light))
                        .accessibilityIdentifier("watchWarmup.pause")

                        Button("Skip") {
                            WatchHaptics.success()
                            model.endWarmup()
                        }
                        .buttonStyle(WatchPillStyle(kind: .destructive))
                        .accessibilityIdentifier("watchWarmup.skip")
                    }
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
