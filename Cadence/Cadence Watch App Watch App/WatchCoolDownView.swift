import SwiftUI
import WatchConnectivity
import CadenceCore
import CadenceFeatures

struct WatchCoolDownView: View {
    let model: WatchStrengthFlowModel

    var body: some View {
        ZStack {
            Color.blue.ignoresSafeArea(.all)

            VStack(spacing: 8) {
                Spacer()
                Text("COOL-DOWN").font(.caption2.bold()).foregroundStyle(.white.opacity(0.8))
                Text(formatTime(TimeInterval(model.cooldownTimerModel.remaining)))
                    .font(.system(size: 52, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.white)
                HStack(spacing: 16) {
                    Button("+1m") {
                        WatchHaptics.tap()
                        model.cooldownTimerModel.add(60)
                    }
                        .foregroundStyle(.white)
                    Button("Skip") {
                        WatchHaptics.success()
                        model.cooldownTimerModel.skip()
                        model.skipCooldown()
                        sendEndSession()
                    }
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("watchCooldown.skip")
                }
                .padding(.top, 8)
                Spacer()
            }
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { t in
                MainActor.assumeIsolated {
                    model.cooldownTimerModel.tick()
                    if model.cooldownTimerModel.remaining <= 0 {
                        t.invalidate()
                        model.completeCooldown()
                        sendEndSession()
                    }
                }
            }
        }
    }

    private func formatTime(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func sendEndSession() {
        guard let payload = model.endSessionPayload() else { return }
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        WCSession.default.transferUserInfo(payload)
    }
}
