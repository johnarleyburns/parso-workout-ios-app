import Foundation
import WatchConnectivity
import CadenceCore
import CadenceFeatures

extension WatchWorkoutManager {
    func requestSettingsSync() {
        phoneSyncState = .syncing(Date())
        lastPhoneSyncError = nil
        guard let session = wcSession, session.activationState == .activated else {
            recordPhoneSyncFailure("Phone unavailable")
            return
        }
        guard session.isReachable else {
            recordPhoneSyncFailure("Open Cladiron on iPhone")
            return
        }
        session.sendMessage(WatchSync.requestSettingsSyncMessage(), replyHandler: nil) { [weak self] error in
            DispatchQueue.main.async {
                self?.recordPhoneSyncFailure(error.localizedDescription)
            }
        }
    }
}

@preconcurrency extension WatchWorkoutManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated, !session.receivedApplicationContext.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            self?.applySettingsContext(session.receivedApplicationContext)
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleMessage(message)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        handleMessage(message)
        replyHandler(["ack": true])
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            self?.applySettingsContext(applicationContext)
        }
    }

    private func handleMessage(_ message: [String: Any]) {
        if message[WatchSync.Key.command] as? String == "start_workout",
           let type = message["type"] as? String {
            startWorkout(type: type)
        } else if message[WatchSync.Key.command] as? String == "stop_workout" {
            stopWorkout(save: false)
        }
    }

    func applySettingsContext(_ applicationContext: [String: Any]) {
        guard let s = watchAppSettings else {
            pendingApplicationContext = applicationContext
            return
        }
        phoneSyncState = .syncing(Date())
        let current = WatchSync.Preferences(
            unit: s.unit,
            distanceUnit: s.distanceUnit,
            intervalColorBlind: s.intervalColorBlind,
            restSeconds: s.restSeconds,
            warmupMinutes: s.warmupMinutes,
            cooldownMinutes: s.cooldownMinutes,
            workoutSounds: s.workoutSounds
        )
        let incoming = current.applying(context: applicationContext)
        s.unit = incoming.unit
        s.distanceUnit = incoming.distanceUnit
        s.intervalColorBlind = incoming.intervalColorBlind
        s.restSeconds = incoming.restSeconds
        s.warmupMinutes = incoming.warmupMinutes
        s.cooldownMinutes = incoming.cooldownMinutes
        s.workoutSounds = incoming.workoutSounds
        recentPartnerNames = incoming.recentPartnerNames
        todayPlan = WatchSync.TodayPlan.from(context: applicationContext)

        let syncedAt = (applicationContext[WatchSync.Key.contextUpdatedAt] as? Date) ?? Date()
        lastPhoneSyncAt = syncedAt
        lastPhoneSyncError = nil
        UserDefaults.standard.set(syncedAt, forKey: "watch.lastPhoneSyncAt")
        phoneSyncState = .synced(syncedAt)
    }

    private func recordPhoneSyncFailure(_ message: String) {
        lastPhoneSyncError = message
        phoneSyncState = .failed(message, lastPhoneSyncAt)
    }
}
