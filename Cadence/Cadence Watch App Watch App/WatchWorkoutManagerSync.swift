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
            recordPhoneSyncFailure(String(localized: "Phone unavailable"))
            return
        }
        let request = WatchSyncHandshake.requestMessage(applied: Self.loadAppliedSyncRecord())
        guard session.isReachable else {
            // Durable fallback: the phone answers with a fresh snapshot when it next runs.
            for transfer in session.outstandingUserInfoTransfers
            where transfer.userInfo[WatchSync.Key.command] as? String == WatchSync.Key.requestSettingsSync {
                transfer.cancel()
            }
            session.transferUserInfo(request)
            recordPhoneSyncFailure(String(localized: "Open Cladiron on iPhone"))
            return
        }
        session.sendMessage(request, replyHandler: nil) { [weak self] error in
            DispatchQueue.main.async {
                self?.recordPhoneSyncFailure(error.localizedDescription)
            }
        }
    }
}

extension WatchWorkoutManager {
    struct AwaitingSyncCommit {
        let envelope: WatchSyncHandshake.Envelope
        let customExercises: [WatchSync.CustomExercise]
        /// Validated phone cardio history to persist before this snapshot is acknowledged; nil = none.
        let cardioHistory: WatchSync.CardioHistorySnapshot?
        let updatedAt: Date
    }
}

extension WatchWorkoutManager: WCSessionDelegate {
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor [weak self] in
            guard let self, reachable else { return }
            self.retryHeartRateOutbox(reason: "reachability")
            guard self.isActive || self.isMonitoring else { return }
            self.sendHeartRateToPhoneSoon()
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
        Task { @MainActor [weak self] in
            WatchSyncSender.flushOutbox()
            self?.retryHeartRateOutbox(reason: "activation")
        }
        let applicationContext = UncheckedWatchPayload(value: session.receivedApplicationContext)
        Task { @MainActor [weak self] in
            guard !applicationContext.value.isEmpty else {
                // Missing context: ask the phone for a snapshot.
                self?.requestSettingsSync()
                return
            }
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
        if WatchHRMessage.isWatchHRPayload(message) { return handleHeartRateProtocol(message) }
        if message["action"] as? String == "cardio_completion_ack",
           let rawID = message["id"] as? String, let id = UUID(uuidString: rawID) {
            acknowledgeCardioCompletion(id)
            return ["ack": true]
        }
        guard let rawAction = message[WatchSync.Key.command] as? String,
              let action = WatchHRCommand.Action(rawValue: rawAction) else { return ["ack": false] }
        let command = WatchHRCommand(payload: message)
        if action == .query { return stateReport(queryIssuedAt: command?.issuedAt).payload }
        let phoneSessionID = command?.phoneWorkoutSessionID
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
                // The phone opened this app with `startWatchApp`, which already
                // started the workout; this command names it.
                if adoptPhoneLaunchedWorkout(requestID: uuid, type: type, phoneWorkoutSessionID: phoneSessionID,
                                              captureEpoch: command?.captureEpoch) {
                    if let command { lastAppliedWatchHRCommandAt = command.issuedAt }
                    return reply(for: uuid, accepted: true)
                }
                return phoneRequestID == nil
                    ? reply(for: uuid, accepted: false, rejection: .watchWorkoutActive)
                    : reply(for: uuid, accepted: false, rejection: .alreadyActive,
                            activeRequestID: phoneRequestID.flatMap(UUID.init(uuidString:)))
            }
            guard startWorkout(type: type, phoneRequestID: uuid, phoneWorkoutSessionID: phoneSessionID,
                                captureEpoch: command?.captureEpoch) else {
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

    static let appliedSyncRecordKey = "watch.syncApplied.v1"

    static func loadAppliedSyncRecord() -> WatchSyncAppliedRecord? {
        UserDefaults.standard.data(forKey: appliedSyncRecordKey)
            .flatMap { try? JSONDecoder().decode(WatchSyncAppliedRecord.self, from: $0) }
    }

    /// Sends an acknowledgement durably (`transferUserInfo`) and, as an optimization, immediately.
    /// Older queued acknowledgements are cancelled so the phone only sees the newest.
    func sendSyncAck(_ ack: WatchSyncHandshake.Ack) {
        guard let session = wcSession, session.activationState == .activated else { return }
        let message = ack.message
        for transfer in session.outstandingUserInfoTransfers
        where WatchSyncHandshake.Ack(message: transfer.userInfo) != nil {
            transfer.cancel()
        }
        session.transferUserInfo(message)
        if session.isReachable { session.sendMessage(message, replyHandler: nil, errorHandler: nil) }
    }

    func applySettingsContext(_ applicationContext: [String: Any]) {
        guard let s = watchAppSettings else {
            pendingApplicationContext = applicationContext
            return
        }
        let applied = Self.loadAppliedSyncRecord()
        let decision = WatchSyncReceiveDecision.decide(context: applicationContext, applied: applied)
        let envelope = WatchSyncHandshake.Envelope(context: applicationContext)
        switch decision {
        case .duplicate:
            if let applied { sendSyncAck(applied.ack) }
            return
        case .stale:
            // Never overwrite newer state; tell the phone what is applied so it can reconcile.
            sendSyncAck(.init(revision: applied?.revision ?? 0, snapshotID: nil, components: nil))
            return
        case .incompatible:
            sendSyncAck(.init(revision: applied?.revision ?? 0, snapshotID: nil, components: nil))
            lastPhoneSyncError = String(localized: "Update Cladiron on iPhone and Watch")
            return
        case .legacy:
            requestSettingsSync()
        case .apply:
            break
        }
        let commitEnvelope = decision == .apply ? envelope : nil
        phoneSyncState = .syncing(Date())
        let current = WatchSync.Preferences(
            unit: s.unit,
            distanceUnit: s.distanceUnit,
            intervalColorBlind: s.intervalColorBlind,
            restSeconds: s.restSeconds,
            warmupMinutes: s.warmupMinutes,
            cooldownMinutes: s.cooldownMinutes,
            workoutSounds: s.workoutSounds,
            spokenCues: s.spokenCues
        )
        let payload = UncheckedWatchPayload(value: applicationContext)
        Task { [weak self] in
            let snapshot = await Task.detached(priority: .utility) {
                WatchSync.IncomingContext.from(
                    context: payload.value,
                    applyingTo: current)
            }.value
            self?.applyIncomingContext(snapshot, envelope: commitEnvelope)
        }
    }

    func applyIncomingContext(_ incoming: WatchSync.IncomingContext, envelope: WatchSyncHandshake.Envelope?) {
        guard let s = watchAppSettings else { return }
        var outcome = WatchSyncCommitCoordinator.Outcome.discard
        var cardioSnapshot: WatchSync.CardioHistorySnapshot?
        switch incoming.cardioHistory {
        case .snapshot(let snapshot): cardioSnapshot = snapshot
        case .absent: break
        case .malformed:
            // Validate the whole payload before any mutation: keep the old projection, never ACK.
            if envelope != nil {
                let applied = Self.loadAppliedSyncRecord()
                sendSyncAck(.init(revision: applied?.revision ?? 0, snapshotID: nil, components: nil))
                recordPhoneSyncFailure(String(localized: "Couldn't read workout history from iPhone"))
                return
            }
        }
        if let envelope {
            // A stale late completion must neither overwrite nor acknowledge newer state.
            outcome = syncCommitCoordinator.accept(envelope, applied: Self.loadAppliedSyncRecord(),
                                                   needsDurableExercises: incoming.customExercises != nil,
                                                   needsDurableCardioHistory: cardioSnapshot != nil)
            if outcome == .discard { return }
        }
        guard applyCoachSuggestion(incoming, isHandshake: envelope != nil) else { return }
        let preferences = incoming.preferences
        s.unit = preferences.unit
        s.distanceUnit = preferences.distanceUnit
        s.intervalColorBlind = preferences.intervalColorBlind
        s.restSeconds = preferences.restSeconds
        s.warmupMinutes = preferences.warmupMinutes
        s.cooldownMinutes = preferences.cooldownMinutes
        s.workoutSounds = preferences.workoutSounds
        s.spokenCues = preferences.spokenCues
        recentPartnerNames = preferences.recentPartnerNames
        todayPlan = incoming.todayPlan
        if let week = incoming.weekSummary { weekSummary = week }
        if let sent = incoming.sentWorkouts { WatchSentWorkoutStore.shared.sentWorkouts = sent }
        if let customExercises = incoming.customExercises {
            pendingCustomExercises = customExercises
            customExercisesUpdatedAt = incoming.updatedAt
        }

        if envelope == nil, let cardioSnapshot { applyCardioHistoryInBackground(cardioSnapshot) }
        if let envelope {
            if outcome == .awaitDurable {
                awaitingSyncCommit = AwaitingSyncCommit(envelope: envelope,
                                                        customExercises: incoming.customExercises ?? [],
                                                        cardioHistory: cardioSnapshot,
                                                        updatedAt: incoming.updatedAt)
                phoneSyncState = .syncing(Date())
                drainDurableSyncCommit()
                return
            }
            if case .commit(let record) = outcome { Self.persistAndAcknowledge(record, via: self) }
        }
        finishSyncApply(updatedAt: incoming.updatedAt)
    }

    func finishSyncApply(updatedAt: Date) {
        lastPhoneSyncAt = updatedAt
        lastPhoneSyncError = nil
        UserDefaults.standard.set(updatedAt, forKey: "watch.lastPhoneSyncAt")
        phoneSyncState = .synced(updatedAt)
    }

    static func persistAndAcknowledge(_ record: WatchSyncAppliedRecord, via manager: WatchWorkoutManager) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        UserDefaults.standard.set(data, forKey: appliedSyncRecordKey)
        manager.sendSyncAck(record.ack)
    }

    func recordPhoneSyncFailure(_ message: String) {
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
