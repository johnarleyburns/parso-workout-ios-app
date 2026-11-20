import SwiftUI
import WatchConnectivity
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures

struct WatchCoolDownView: View {
    let model: WatchStrengthFlowModel
    @State private var timerController = WatchCooldownTimerController()
    @Environment(WatchWorkoutManager.self) private var watchManager

    var body: some View {
        ZStack {
            Color.blue.ignoresSafeArea(.all)

            VStack(spacing: 8) {
                // `minLength` (not a plain Spacer) guarantees this never
                // shrinks to zero and lets the caption sit under the system
                // clock/status area at the top of the screen.
                Spacer(minLength: 20)
                Text("COOL-DOWN").font(.caption2.bold()).foregroundStyle(.white.opacity(0.8))
                Text(formatTime(TimeInterval(model.cooldownTimerModel.remaining)))
                    .font(.system(size: 52, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.white)
                WatchLiveHeartRateBadge(bpm: watchManager.currentBPM)
                VStack(spacing: 6) {
                    Button("+1 min") {
                        WatchHaptics.tap()
                        model.cooldownTimerModel.add(60)
                    }
                    .buttonStyle(WatchPillStyle(kind: .secondary, small: true))
                    .accessibilityIdentifier("watchCooldown.add")

                    Button("+5 min") {
                        WatchHaptics.tap()
                        model.cooldownTimerModel.add(300)
                    }
                    .buttonStyle(WatchPillStyle(kind: .secondary, small: true))
                    .accessibilityIdentifier("watchCooldown.addFiveMinutes")

                    // Same two-action grammar as the workout: Pause/Resume on
                    // the left, End on the right. End finishes immediately.
                    HStack(spacing: 6) {
                        Button(model.cooldownTimerModel.isPaused ? "Resume" : "Pause") {
                            WatchHaptics.tap()
                            if model.cooldownTimerModel.isPaused {
                                model.cooldownTimerModel.resume()
                            } else {
                                model.cooldownTimerModel.pause()
                            }
                        }
                        .buttonStyle(WatchPillStyle(kind: .light))
                        .accessibilityIdentifier("watchCooldown.pause")

                        Button("End") {
                            endCooldown()
                        }
                        .buttonStyle(WatchPillStyle(kind: .primary))
                        .accessibilityIdentifier("watchCooldown.end")
                    }
                }
                .padding(.top, 8)
                Spacer()
            }
        }
        .onAppear {
            timerController.start(model: model, watchManager: watchManager)
        }
    }

    private func endCooldown() {
        WatchHaptics.success()
        model.cooldownTimerModel.skip()
        let samples = watchManager.finalizeStrengthHRCapture().samples
        model.skipCooldown()
        watchManager.completeStrengthWorkout(model: model, capture: samples)
    }

    private func formatTime(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

@MainActor
private final class WatchCooldownTimerController {
    private var timer: Timer?
    private weak var model: WatchStrengthFlowModel?
    private weak var watchManager: WatchWorkoutManager?

    func start(model: WatchStrengthFlowModel, watchManager: WatchWorkoutManager) {
        self.model = model
        self.watchManager = watchManager
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let model = self.model else { return }
                model.cooldownTimerModel.tick()
                if model.cooldownTimerModel.remaining <= 0 {
                    self.timer?.invalidate()
                    self.timer = nil
                    let samples = self.watchManager?.finalizeStrengthHRCapture().samples
                    model.completeCooldown()
                    self.watchManager?.completeStrengthWorkout(model: model, capture: samples)
                }
            }
        }
    }
}
