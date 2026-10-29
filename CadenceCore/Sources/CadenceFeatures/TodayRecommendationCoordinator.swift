import Foundation

/// Which root screen is running the shared coach lifecycle.
public enum TodayCacheSurface: Equatable, Sendable {
    case today
    case thisWeek
}

/// Owns the Today recommendation cache (in-process snapshot + durable stores).
///
/// Ownership boundary, enforced in code: only `.today` may write or invalidate
/// the cache or restore (and thereby discard) the durable record. `.thisWeek`
/// calls are no-ops; This Week keeps its computed snapshot surface-locally.
/// Shared coach inputs that really change are covered by the deterministic
/// fingerprint, so Today recomputes on its own even when This Week is silent.
///
/// Persistence (saves and invalidations) runs on ONE serial chain, and each
/// save carries the invalidation epoch it was issued under, so a save queued
/// before an invalidation can never repopulate the record afterwards.
@MainActor
public final class TodayRecommendationCoordinator<Snapshot> {
    private var entry: (fingerprint: String, passiveStamp: String, value: Snapshot)?
    private var persistence: Task<Void, Never>?
    private var epoch = 0

    /// Last durable record shown provisionally, awaiting stable-input validation.
    private var provisional: TodayProvisionalRecord?
    public private(set) var lastOutcome: TodayCacheOutcome?
    /// Observability hook (e.g. os.Logger); receives outcomes only, no content.
    public var outcomeObserver: (@MainActor (TodayCacheOutcome) -> Void)?
    /// Receives the semantic reason for each deliberate invalidation.
    public var invalidationObserver: (@MainActor (TodayCacheInvalidationReason) -> Void)?
    /// Last durable write failure (nil after a successful write); diagnosable.
    public private(set) var lastWriteFailure: String?

    public let recommendationStore: TodayRecommendationCacheStore
    public let suggestionStore: TodaySuggestedWorkoutCacheStore

    public init(recommendationStore: TodayRecommendationCacheStore,
                suggestionStore: TodaySuggestedWorkoutCacheStore) {
        self.recommendationStore = recommendationStore
        self.suggestionStore = suggestionStore
    }

    /// In-process hit. `passiveStamp == nil` = HealthKit readiness not loaded yet.
    public func cachedSnapshot(fingerprint: String, passiveStamp: String?) -> Snapshot? {
        guard let entry, entry.fingerprint == fingerprint,
              passiveStamp == nil || entry.passiveStamp == passiveStamp else { return nil }
        return entry.value
    }

    /// Returns false (and touches nothing) unless the caller is Today.
    @discardableResult
    public func store(_ value: Snapshot, payload: TodayRecommendationPayload,
                      fingerprint: String, passiveStamp: String,
                      surface: TodayCacheSurface) -> Bool {
        guard surface == .today else { return false }
        entry = (fingerprint, passiveStamp, value)
        let issuedEpoch = epoch
        let store = recommendationStore
        enqueue { [weak self] in
            guard let self, self.epoch == issuedEpoch else { return }
            let result = await store.save(payload, fingerprint: fingerprint, passiveStamp: passiveStamp)
            self.noteWrite(result)
        }
        return true
    }

    /// Invalidation for history / preference / readiness changes. Today only.
    public func invalidate(surface: TodayCacheSurface,
                           reason: TodayCacheInvalidationReason = .historyChanged) {
        guard surface == .today else { return }
        invalidationObserver?(reason)
        record(.invalidated)
        entry = nil
        provisional = nil
        epoch += 1
        let plans = suggestionStore, recs = recommendationStore
        enqueue {
            await plans.invalidate()
            await recs.invalidate()
        }
    }

    /// Drops only the suggested-plan record (Today only). The hero record is
    /// left for `store` to replace atomically once the recompute finishes.
    public func invalidateSuggestion(surface: TodayCacheSurface,
                                     reason: TodayCacheInvalidationReason = .historyChanged) {
        guard surface == .today else { return }
        invalidationObserver?(reason)
        record(.invalidated)
        let plans = suggestionStore
        enqueue { await plans.invalidate() }
    }

    private func noteWrite(_ result: TodayCacheWriteResult) {
        switch result {
        case .saved: lastWriteFailure = nil
        case .failed(let why): lastWriteFailure = why; record(.writeFailed)
        }
    }

    /// Lets queued saves/invalidations reach disk before a restore reads it.
    public func settle() async { await persistence?.value }

    /// Durable restore for Today's hero. This Week never reads (or discards) it.
    public func restoreDurable(fingerprint: String, passiveStamp: String?, surface: TodayCacheSurface)
        async -> (payload: TodayRecommendationPayload, passiveStamp: String)? {
        guard surface == .today else { return nil }
        await settle()
        return await recommendationStore.restore(fingerprint: fingerprint, passiveStamp: passiveStamp)
    }

    /// Cold-launch restore for display only. Never compares fingerprints, so a
    /// transient startup mismatch cannot erase a same-day record. Today only.
    public func restoreProvisional(surface: TodayCacheSurface) async -> TodayProvisionalRecord? {
        guard surface == .today else { return nil }
        await settle()
        let result = await recommendationStore.peekDisplayable()
        provisional = result.record
        record(result.outcome)
        return result.record
    }

    /// Strict freshness check once inputs are stable. Returns true when the
    /// provisional record still matches. A mismatch deletes nothing: the caller
    /// recomputes and `store` atomically replaces the record.
    @discardableResult
    public func reconcileProvisional(stableFingerprint: String, stablePassiveStamp: String,
                                     surface: TodayCacheSurface) -> Bool {
        guard surface == .today, let provisional else { return false }
        let matches = provisional.fingerprint == stableFingerprint
            && provisional.passiveStamp == stablePassiveStamp
        self.provisional = nil
        record(matches ? .stableMatch : .stableInvalidation)
        return matches
    }

    private func record(_ outcome: TodayCacheOutcome) {
        lastOutcome = outcome
        outcomeObserver?(outcome)
    }

    private func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let previous = persistence
        persistence = Task {
            await previous?.value
            await work()
        }
    }
}
