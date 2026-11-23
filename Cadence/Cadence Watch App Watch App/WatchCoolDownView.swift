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
        WatchPhaseTimerView(
            title: WatchPhasePresentation.coolDownTitle,
            tint: .orange,
            remaining: model.cooldownTimerModel.remaining,
            isPaused: model.cooldownTimerModel.isPaused,
            bpm: watchManager.currentBPM,
            centerSystemImage: WatchPhasePresentation.endSystemImage,
            centerAccessibilityLabel: Text("End"),
            identifierPrefix: "watchCooldown",
            centerAccessibilityIdentifier: "watchCooldown.end",
            onPause: {
                WatchHaptics.tap()
                if model.cooldownTimerModel.isPaused {
                    model.cooldownTimerModel.resume()
                } else {
                    model.cooldownTimerModel.pause()
                }
            },
            onCenter: {
                endCooldown()
            },
            onAddOneMinute: {
                WatchHaptics.tap()
                model.cooldownTimerModel.add(60)
            })
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
