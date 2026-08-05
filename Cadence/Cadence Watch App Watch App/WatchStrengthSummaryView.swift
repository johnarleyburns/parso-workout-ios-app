import SwiftUI
import WatchConnectivity
import CadenceCore
import CadenceFeatures

struct WatchStrengthSummaryView: View {
    let model: WatchStrengthFlowModel
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 28)).foregroundStyle(.green)
            Text("Saved").font(.headline)
                .accessibilityIdentifier("watchSummary.saved")

            summaryRow("Duration", model.durationText)

            Button("Done") {
                sendEndSession()
                onDismiss()
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
            .accessibilityIdentifier("watchSummary.done")
            Spacer()
        }
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption.bold()).monospacedDigit()
        }
        .padding(.horizontal, 20)
    }

    private func sendEndSession() {
        guard let payload = model.endSessionPayload() else { return }
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        WCSession.default.transferUserInfo(payload)
    }
}
