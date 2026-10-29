import Foundation
import CadenceFeatures

extension WatchWorkoutManager {
    /// The envelope only if unexpired and well-formed right now; expired data is diagnostic only.
    var startableCoachSuggestion: WatchCoachSuggestionEnvelope? {
        coachSuggestionCoordinator.startable(now: Date())
    }

    /// Restores the durable envelope (offline relaunch) and watches for Watch-local history changes.
    func startCoachSuggestionLifecycle() {
        coachSuggestionEnvelope = coachSuggestionCoordinator.current
        localHistoryObserver = NotificationCenter.default.addObserver(
            forName: WatchLocalHistoryMutation.name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.invalidateCoachSuggestionForLocalHistory() }
            }
    }

    /// Persists (or removes) the Coach snapshot before anything is acknowledged. A rejected payload or
    /// failed write keeps the prior envelope, withholds the ACK, and returns false.
    func applyCoachSuggestion(_ incoming: WatchSync.IncomingContext, isHandshake: Bool) -> Bool {
        let outcome = coachSuggestionCoordinator.apply(incoming.coachSuggestion, isHandshakeSnapshot: isHandshake)
        coachSuggestionEnvelope = coachSuggestionCoordinator.current
        guard outcome == .rejected else { return true }
        syncCommitCoordinator = WatchSyncCommitCoordinator(
            appliedRevision: Self.loadAppliedSyncRecord()?.revision ?? 0)
        recordPhoneSyncFailure(String(localized: "Couldn't save Coach suggestion. Retrying."))
        return false
    }

    /// A Watch-only strength change makes the stored snapshot stale: drop it now (works offline),
    /// then ask the phone for a fresh one opportunistically.
    func invalidateCoachSuggestionForLocalHistory() {
        let hadSnapshot = coachSuggestionEnvelope != nil
        coachSuggestionCoordinator.invalidate(now: Date())
        coachSuggestionEnvelope = nil
        // Per-set logging fires this too; only the first call after a snapshot needs a refresh.
        if hadSnapshot { requestSettingsSync() }
    }
}
