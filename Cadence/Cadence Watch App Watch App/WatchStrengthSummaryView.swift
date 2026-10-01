import SwiftUI
import WatchConnectivity
import CadenceCore
import CadenceFeatures

/// Watch redesign §5 F2 — saved, with receipts: each destination shows its real state (Transparency
/// HARD RULE). Strength summaries reach Apple Health from the iPhone once it has the sets, so that
/// row says so. A failed send offers Retry; Done never waits on the phone.
struct WatchStrengthSummaryView: View {
    let model: WatchStrengthFlowModel
    let onDismiss: () -> Void
    @Environment(WatchWorkoutManager.self) private var watchManager
    @State private var sentEnd = false
    @State private var receipt = WatchSaveReceipt.make(savedOnWatch: true, pendingTransfers: 0,
                                                       phoneReachable: false, transferError: nil)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(WatchTone.accent)
                    Text("Saved").font(.headline)
                        .accessibilityIdentifier("watchSummary.saved")
                }
                Text(verbatim: "\(model.durationText) · \(model.setCount) · \(model.weightValue(model.volume)) \(model.unit.abbreviation)")
                    .font(.caption2).foregroundStyle(.secondary)
                    .accessibilityLabel(Text("Duration \(model.durationText)") + Text(verbatim: ", ") + Text("\(model.setCount) sets"))
                WatchReceiptRow(title: "Saved on watch", state: receipt.watch)
                WatchReceiptRow(title: "iPhone", state: receipt.iPhone)
                WatchReceiptRow(title: "Apple Health", state: receipt.health)
                if case .failed = receipt.iPhone {
                    Button("Retry") { sendEnd(force: true) }
                        .buttonStyle(WatchPillStyle(kind: .secondary, small: true))
                        .accessibilityIdentifier("watchSummary.retry")
                }
                Button("Done") {
                    WatchHaptics.success()
                    sendEnd(force: false)
                    onDismiss()
                }
                .buttonStyle(WatchPillStyle(kind: .primary))
                .handGestureShortcut(.primaryAction)
                .accessibilityIdentifier("watchSummary.done")
            }
            .padding(.horizontal, 4)
        }
        .task {
            sendEnd(force: false)
            while !Task.isCancelled {
                refreshReceipt()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func refreshReceipt() {
        let reachable = WCSession.isSupported() && WCSession.default.activationState == .activated && WCSession.default.isReachable
        // The WCSession delegate records real transfer failures (didFinish userInfoTransfer:error:).
        let error = watchManager.lastPhoneSyncError
        receipt = WatchSaveReceipt.make(savedOnWatch: true, pendingTransfers: WatchSyncSender.pendingTransfers,
                                        phoneReachable: reachable, transferError: error)
    }

    private func sendEnd(force: Bool) {
        guard force || !sentEnd, let payload = model.endSessionPayload() else { return }
        sentEnd = true
        WatchSyncSender.send(payload)
    }
}
