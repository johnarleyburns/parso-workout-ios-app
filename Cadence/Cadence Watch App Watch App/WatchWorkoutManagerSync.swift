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
            _ = self?.handleMessage(message.value)
        }
    }

    @MainActor
    func handleMessage(_ message: [String: Any]) -> [String: Any] {
        guard let rawAction = message[WatchSync.Key.command] as? String,
              let action = WatchHRCommand.Action(rawValue: rawAction) else { return ["ack": false] }
        let command = WatchHRCommand(payload: message)
        if let command, !command.isNewer(than: lastAppliedWatchHRCommandAt) {
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
        if let rows = applicationContext[WatchSync.Key.customExercises] as? [[String: Any]] {
            customExerciseRows = rows
            customExercisesUpdatedAt = syncedAt
        }

        lastPhoneSyncAt = syncedAt
        lastPhoneSyncError = nil
        UserDefaults.standard.set(syncedAt, forKey: "watch.lastPhoneSyncAt")
        phoneSyncState = .synced(syncedAt)
    }

    func applyCustomExercises(_ raw: Any?, in context: ModelContext) {
        guard let rows = raw as? [[String: Any]] else { return }
        for row in rows {
            guard let incoming = WatchSync.CustomExercise(propertyList: row) else { continue }
            let existing = (try? WorkoutRepository.allExercises(context))?.first {
                $0.id == incoming.id || $0.name.compare(incoming.name, options: .caseInsensitive) == .orderedSame
            }
            let exercise = existing ?? Exercise(id: incoming.id, name: incoming.name, isCustom: true)
            if existing == nil { context.insert(exercise) }
            exercise.name = incoming.name
            exercise.isCustom = true
            exercise.category = incoming.category
            exercise.equipment = incoming.equipment
            exercise.mechanics = incoming.mechanics
            exercise.force = incoming.force
            exercise.primaryMuscles = incoming.primaryMuscles
            exercise.secondaryMuscles = incoming.secondaryMuscles
            exercise.searchKeywords = incoming.searchKeywords
            exercise.isLateral = incoming.isLateral
            exercise.updatedAt = incoming.updatedAt
        }
        try? context.save()
    }

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
