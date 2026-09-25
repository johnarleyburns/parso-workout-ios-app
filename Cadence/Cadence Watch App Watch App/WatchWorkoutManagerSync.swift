import Foundation
import SwiftData
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

extension WatchWorkoutManager: WCSessionDelegate {
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor [weak self] in
            guard let self, reachable, self.isActive || self.isMonitoring,
                  let bpm = self.currentBPM else { return }
            self.relayBPM(bpm)
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
        let applicationContext = UncheckedWatchPayload(value: session.receivedApplicationContext)
        guard !applicationContext.value.isEmpty else { return }
        Task { @MainActor [weak self] in
            self?.applySettingsContext(applicationContext.value)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let message = UncheckedWatchPayload(value: message)
        Task { @MainActor [weak self] in
            _ = self?.handleMessage(message.value)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        let message = UncheckedWatchPayload(value: message)
        let replyHandler = UncheckedWatchReplyHandler(replyHandler)
        Task { @MainActor [weak self] in
            replyHandler.call(self?.handleMessage(message.value) ?? ["ack": false])
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let applicationContext = UncheckedWatchPayload(value: applicationContext)
        Task { @MainActor [weak self] in
            self?.applySettingsContext(applicationContext.value)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        let message = UncheckedWatchPayload(value: userInfo)
        Task { @MainActor [weak self] in
            guard let self else { return }
            let reply = self.handleMessage(message.value)
            // User-info has no replyHandler. Mirror the command result over an
            // immediate message when possible so the phone can advance from
            // connecting even when the durable delivery was the one that
            // started the session.
            if reply["requestID"] != nil, self.wcSession?.isReachable == true {
                self.wcSession?.sendMessage(reply, replyHandler: nil, errorHandler: nil)
            }
        }
    }

    @MainActor
    func handleMessage(_ message: [String: Any]) -> [String: Any] {
        if message["action"] as? String == "cardio_completion_ack",
           let rawID = message["id"] as? String, let id = UUID(uuidString: rawID) {
            acknowledgeCardioCompletion(id)
            return ["ack": true]
        }
        guard let rawAction = message[WatchSync.Key.command] as? String,
              let action = WatchHRCommand.Action(rawValue: rawAction) else { return ["ack": false] }
        let command = WatchHRCommand(payload: message)
        if let command, !command.isNewer(than: lastAppliedWatchHRCommandAt) {
            if action == .start,
               let requestID = command.requestID,
               requestID.uuidString == phoneRequestID,
               isActive || isMonitoring {
                return reply(for: requestID, accepted: true)
            }
            return ["ack": true]
        }

        if action == .start,
           let type = message["type"] as? String,
           let requestID = message["requestID"] as? String,
           let uuid = UUID(uuidString: requestID) {
            guard !isActive, !isMonitoring else {
                return phoneRequestID == nil
                    ? reply(for: uuid, accepted: false, rejection: .watchWorkoutActive)
                    : reply(for: uuid, accepted: false, rejection: .alreadyActive,
                            activeRequestID: phoneRequestID.flatMap(UUID.init(uuidString:)))
            }
            guard startWorkout(type: type, phoneRequestID: uuid) else {
                return reply(for: uuid, accepted: false, rejection: .sessionStartFailed)
            }
            if let command { lastAppliedWatchHRCommandAt = command.issuedAt }
            return reply(for: uuid, accepted: true)
        } else if action == .stop {
            // A stop may only own a phone-started session. Legacy unscoped stop
            // messages remain compatible, but can never kill a watch-only one.
            guard let phoneRequestID else { return ["ack": true] }
            if let expected = message["requestID"] as? String, expected != phoneRequestID {
                return ["ack": false]
            }
            if let command { lastAppliedWatchHRCommandAt = command.issuedAt }
            stopWorkout(save: false)
            return ["ack": true]
        }
        return ["ack": false]
    }

    private var lastAppliedWatchHRCommandAt: TimeInterval? {
        get {
            let value = UserDefaults.standard.double(forKey: "watchHR.lastAppliedCommandAt")
            return value == 0 ? nil : value
        }
        set { UserDefaults.standard.set(newValue, forKey: "watchHR.lastAppliedCommandAt") }
    }

    private func reply(for requestID: UUID, accepted: Bool, rejection: WatchHRRejection? = nil,
                       activeRequestID: UUID? = nil) -> [String: Any] {
        var result: [String: Any] = ["ack": accepted, "accepted": accepted, "requestID": requestID.uuidString]
        if let rejection { result["rejection"] = rejection.rawValue }
        if let activeRequestID { result["activeRequestID"] = activeRequestID.uuidString }
        return result
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
        let payload = UncheckedWatchPayload(value: applicationContext)
        Task { [weak self] in
            let snapshot = await Task.detached(priority: .utility) {
                WatchSync.IncomingContext.from(
                    context: payload.value,
                    applyingTo: current)
            }.value
            self?.applyIncomingContext(snapshot)
        }
    }

    private func applyIncomingContext(_ incoming: WatchSync.IncomingContext) {
        guard let s = watchAppSettings else { return }
        let preferences = incoming.preferences
        s.unit = preferences.unit
        s.distanceUnit = preferences.distanceUnit
        s.intervalColorBlind = preferences.intervalColorBlind
        s.restSeconds = preferences.restSeconds
        s.warmupMinutes = preferences.warmupMinutes
        s.cooldownMinutes = preferences.cooldownMinutes
        s.workoutSounds = preferences.workoutSounds
        recentPartnerNames = preferences.recentPartnerNames
        todayPlan = incoming.todayPlan
        if let customExercises = incoming.customExercises {
            pendingCustomExercises = customExercises
            customExercisesUpdatedAt = incoming.updatedAt
        }

        lastPhoneSyncAt = incoming.updatedAt
        lastPhoneSyncError = nil
        UserDefaults.standard.set(incoming.updatedAt, forKey: "watch.lastPhoneSyncAt")
        phoneSyncState = .synced(incoming.updatedAt)
    }

    /// Stores the phone's custom exercises off the main actor.
    ///
    /// This used to run on the main actor at every launch (WatchConnectivity
    /// replays the last context on activation), fetching the whole catalog once
    /// per custom exercise and saving unconditionally, which kept the Watch
    /// unresponsive for seconds. Now an unchanged list is skipped by
    /// fingerprint, and a changed one is written once on a background context.
    func applyCustomExercisesInBackground(container: ModelContainer) {
        let incoming = pendingCustomExercises
        let fingerprint = WatchSync.CustomExercise.fingerprint(incoming)
        guard fingerprint != UserDefaults.standard.string(forKey: Self.appliedCustomExercisesKey),
              fingerprint != customExerciseApplyingFingerprint else { return }
        customExerciseApplyingFingerprint = fingerprint
        let previous = customExerciseApplyTask
        customExerciseApplyTask = Task.detached(priority: .utility) { [weak self] in
            await previous?.value
            let context = ModelContext(container)
            let applied = (try? WatchCustomExerciseStore.apply(incoming, in: context)) != nil
            await self?.finishCustomExerciseApply(fingerprint: fingerprint, applied: applied)
        }
    }

    /// Records a stored list so the next identical replay is skipped. A failed
    /// write records nothing, so the next replay retries it.
    private func finishCustomExerciseApply(fingerprint: String, applied: Bool) {
        if applied {
            UserDefaults.standard.set(fingerprint, forKey: Self.appliedCustomExercisesKey)
        }
        if customExerciseApplyingFingerprint == fingerprint {
            customExerciseApplyingFingerprint = nil
        }
    }

    static let appliedCustomExercisesKey = "watch.customExercises.appliedFingerprint"

    private func recordPhoneSyncFailure(_ message: String) {
        lastPhoneSyncError = message
        phoneSyncState = .failed(message, lastPhoneSyncAt)
    }
}

/// WatchConnectivity guarantees property-list payloads at this framework
/// boundary. The framework types predate Swift concurrency annotations, so
/// carry them across the delegate queue explicitly and consume them once on
/// MainActor.
private struct UncheckedWatchPayload: @unchecked Sendable {
    let value: [String: Any]
}

private struct UncheckedWatchReplyHandler: @unchecked Sendable {
    let call: ([String: Any]) -> Void

    init(_ call: @escaping ([String: Any]) -> Void) {
        self.call = call
    }
}
