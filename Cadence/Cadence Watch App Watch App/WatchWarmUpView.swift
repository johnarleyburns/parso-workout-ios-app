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
        WatchPhaseTimerView(
            title: WatchPhasePresentation.warmUpTitle,
            tint: .orange,
            remaining: model.warmupTimerModel.remaining,
            isPaused: model.warmupTimerModel.isPaused,
            bpm: watchManager.currentBPM,
            centerSystemImage: WatchWarmUpControlPresentation.skipSystemImage,
            centerAccessibilityLabel: Text("Skip"),
            identifierPrefix: "watchWarmup",
            centerAccessibilityIdentifier: "watchWarmup.skip",
            onPause: {
                WatchHaptics.tap()
                if model.warmupTimerModel.isPaused {
                    model.warmupTimerModel.resume()
                } else {
                    model.warmupTimerModel.pause()
                }
            },
            onCenter: {
                WatchHaptics.success()
                model.endWarmup()
            },
            onAddOneMinute: {
                WatchHaptics.tap()
                model.warmupTimerModel.add(60)
            })
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
}
