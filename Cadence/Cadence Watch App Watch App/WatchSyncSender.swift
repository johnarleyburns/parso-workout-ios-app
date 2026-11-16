import Foundation
import WatchConnectivity

/// One place that hands a flow payload to WatchConnectivity (durable user-info transfer).
enum WatchSyncSender {
    /// Payloads created while WatchConnectivity isn't activated yet (cold launch, no iPhone paired
    /// yet). They used to be dropped; now they wait here, survive relaunch, and go on activation.
    private static let outboxKey = "watch.sync.outbox"

    static func send(_ payload: [String: Any]) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else {
            var outbox = UserDefaults.standard.array(forKey: outboxKey) as? [[String: Any]] ?? []
            outbox.append(payload)
            UserDefaults.standard.set(outbox, forKey: outboxKey)
            return
        }
        WCSession.default.transferUserInfo(payload)
    }

    /// Called when the session activates: hands every waiting payload to WatchConnectivity in order.
    static func flushOutbox() {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated,
              let outbox = UserDefaults.standard.array(forKey: outboxKey) as? [[String: Any]], !outbox.isEmpty
        else { return }
        UserDefaults.standard.removeObject(forKey: outboxKey)
        for payload in outbox { WCSession.default.transferUserInfo(payload) }
    }

    /// Transfers not yet delivered to the phone (F2 receipts): WatchConnectivity's queue plus the outbox.
    static var pendingTransfers: Int {
        let waiting = (UserDefaults.standard.array(forKey: outboxKey) as? [[String: Any]])?.count ?? 0
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return waiting }
        return waiting + WCSession.default.outstandingUserInfoTransfers.count
    }
}
