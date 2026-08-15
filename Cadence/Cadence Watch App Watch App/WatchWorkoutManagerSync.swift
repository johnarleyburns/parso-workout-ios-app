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

extension WatchWorkoutManager: @preconcurrency WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated, !session.receivedApplicationContext.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            self?.applySettingsContext(session.receivedApplicationContext)
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        _ = handleMessage(message)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        replyHandler(handleMessage(message))
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            self?.applySettingsContext(applicationContext)
        }
    }

    private func handleMessage(_ message: [String: Any]) -> [String: Any] {
        if message[WatchSync.Key.command] as? String == "start_workout",
           let type = message["type"] as? String,
           let requestID = message["requestID"] as? String,
           let uuid = UUID(uuidString: requestID) {
            guard !isActive, !isMonitoring else {
                return reply(for: uuid, accepted: false, rejection: .alreadyActive)
            }
            phoneRequestID = requestID
            startWorkout(type: type)
            return reply(for: uuid, accepted: true)
        } else if message[WatchSync.Key.command] as? String == "stop_workout" {
            if let expected = message["requestID"] as? String, expected != phoneRequestID {
                return ["ack": false]
            }
            stopWorkout(save: false)
            phoneRequestID = nil
            return ["ack": true]
        }
        return ["ack": false]
    }

    private func reply(for requestID: UUID, accepted: Bool, rejection: WatchHRRejection? = nil) -> [String: Any] {
        var result: [String: Any] = ["ack": accepted, "accepted": accepted, "requestID": requestID.uuidString]
        if let rejection { result["rejection"] = rejection.rawValue }
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
