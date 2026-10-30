import Foundation
import SwiftData
import CadenceCore
import CadenceFeatures

/// Durable (store-backed) half of the phone→Watch handshake: custom exercises and the
/// phone-mirrored cardio history are saved here, and the ACK is sent only after they succeed.
extension WatchWorkoutManager {
    /// Persists the awaiting snapshot's custom exercises, then commits. ACK is
    /// sent only from `completeDurableSyncCommit` after the store succeeded.
    func drainDurableSyncCommit() {
        guard let container = syncModelContainer, let awaiting = awaitingSyncCommit,
              durableCommitEnvelopeID != awaiting.envelope.snapshotID else { return }
        let envelope = awaiting.envelope
        let incoming = awaiting.customExercises
        let cardioHistory = awaiting.cardioHistory
        let fingerprint = WatchSync.CustomExercise.fingerprint(incoming)
        let exercisesUnchanged = fingerprint == UserDefaults.standard.string(forKey: Self.appliedCustomExercisesKey)
        if exercisesUnchanged && cardioHistory == nil {
            completeDurableSyncCommit(envelope: envelope, succeeded: true)
            return
        }
        durableCommitEnvelopeID = envelope.snapshotID
        let previous = customExerciseApplyTask
        customExerciseApplyTask = Task.detached(priority: .utility) { [weak self] in
            await previous?.value
            let context = ModelContext(container)
            var applied = true
            if !exercisesUnchanged {
                applied = (try? WatchCustomExerciseStore.apply(incoming, in: context)) != nil
                await self?.finishCustomExerciseApply(fingerprint: fingerprint, applied: applied)
            }
            // The ACK barrier covers cardio history too: a failed save leaves the old projection.
            if applied, let cardioHistory {
                applied = (try? WatchCardioHistoryStore.apply(cardioHistory, in: context)) != nil
                if applied { await self?.cardioHistoryDidPersist() }
            }
            await self?.completeDurableSyncCommit(envelope: envelope, succeeded: applied)
        }
    }

    func completeDurableSyncCommit(envelope: WatchSyncHandshake.Envelope, succeeded: Bool) {
        if durableCommitEnvelopeID == envelope.snapshotID { durableCommitEnvelopeID = nil }
        guard let awaiting = awaitingSyncCommit, awaiting.envelope == envelope else { return }
        let outcome = syncCommitCoordinator.durableStoreFinished(
            for: envelope, succeeded: succeeded, applied: Self.loadAppliedSyncRecord())
        switch outcome {
        case .commit(let record):
            awaitingSyncCommit = nil
            Self.persistAndAcknowledge(record, via: self)
            finishSyncApply(updatedAt: awaiting.updatedAt)
        case .failed:
            // Old confirmed revision stays; no ACK, so the phone keeps it pending and retries.
            awaitingSyncCommit = nil
            requestSettingsSync()
            recordPhoneSyncFailure(String(localized: "Couldn't save synced data. Retrying."))
        case .discard, .awaitDurable:
            awaitingSyncCommit = nil
        }
    }

    /// Stores the phone's custom exercises off the main actor.
    ///
    /// This used to run on the main actor at every launch (WatchConnectivity
    /// replays the last context on activation), fetching the whole catalog once
    /// per custom exercise and saving unconditionally, which kept the Watch
    /// unresponsive for seconds. Now an unchanged list is skipped by
    /// fingerprint, and a changed one is written once on a background context.
    func applyCustomExercisesInBackground(container: ModelContainer) {
        syncModelContainer = container
        // A snapshot awaiting durable custom exercises owns this write; it commits and ACKs afterwards.
        if awaitingSyncCommit != nil { drainDurableSyncCommit(); return }
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

    /// Un-acknowledged (pre-handshake) contexts: store the phone's cardio history off the main actor.
    /// Nothing is acknowledged from here; the handshake path owns ACKs.
    func applyCardioHistoryInBackground(_ snapshot: WatchSync.CardioHistorySnapshot) {
        guard let container = syncModelContainer else { return }
        let previous = customExerciseApplyTask
        customExerciseApplyTask = Task.detached(priority: .utility) { [weak self] in
            await previous?.value
            let context = ModelContext(container)
            if (try? WatchCardioHistoryStore.apply(snapshot, in: context)) != nil {
                await self?.cardioHistoryDidPersist()
            }
        }
    }

    /// Emitted only after the projection was saved, so the visible list never refreshes early.
    func cardioHistoryDidPersist() { cardioHistoryRevision += 1 }

    /// Records a stored list so the next identical replay is skipped. A failed
    /// write records nothing, so the next replay retries it.
    func finishCustomExerciseApply(fingerprint: String, applied: Bool) {
        if applied {
            UserDefaults.standard.set(fingerprint, forKey: Self.appliedCustomExercisesKey)
        }
        if customExerciseApplyingFingerprint == fingerprint {
            customExerciseApplyingFingerprint = nil
        }
    }

    static let appliedCustomExercisesKey = "watch.customExercises.appliedFingerprint"
}
