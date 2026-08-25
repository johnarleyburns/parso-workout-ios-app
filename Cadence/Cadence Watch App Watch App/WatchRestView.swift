import SwiftUI
import CadenceCore
import CadenceFeatures

struct WatchRestView: View {
    let model: WatchStrengthFlowModel

    @Environment(AppSettings.self) private var watchSettings
    @Environment(WatchWorkoutManager.self) private var watchManager
    @State private var timer: Timer?
    @State private var cues = WatchIntervalCuePlayer()

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Text("REST").font(.caption.bold()).foregroundStyle(.secondary)
            Text(formatTime(TimeInterval(model.restTimer.remaining)))
                .font(.system(size: 52, weight: .heavy, design: .monospaced))

            Label(watchManager.currentBPM.map { "\(Int($0)) BPM" } ?? "-- BPM",
                  systemImage: "heart.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.red)

            if model.restTimer.isRunning {
                ProgressView(value: model.restTimer.progress)
                    .tint(.green)
                    .padding(.horizontal, 20)
            }

            HStack(spacing: 12) {
                Button("+30s") {
                    WatchHaptics.tap()
                    model.addRestTime(30)
                }
                .buttonStyle(.bordered)
                Button("Next Set") {
                    WatchHaptics.tap()
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
                Task { @MainActor in
                    let wasRunning = model.restTimer.isRunning
                    model.restTimer.tick()
                    if wasRunning, !model.restTimer.isRunning, model.restTimer.remaining == 0 {
                        cues.restComplete(soundsEnabled: watchSettings.workoutSounds)
                        WatchHaptics.success()
                    }
                }
            }
        }
        .onDisappear {
            timer?.invalidate()
            cues.stop()
        }
    }

    private func formatTime(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
