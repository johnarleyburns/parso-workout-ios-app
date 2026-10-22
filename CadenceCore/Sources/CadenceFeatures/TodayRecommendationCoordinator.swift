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
            await store.save(payload, fingerprint: fingerprint, passiveStamp: passiveStamp)
        }
        return true
    }

    /// Invalidation for history / preference / readiness changes. Today only.
    public func invalidate(surface: TodayCacheSurface) {
        guard surface == .today else { return }
        entry = nil
        epoch += 1
        let plans = suggestionStore, recs = recommendationStore
        enqueue {
            await plans.invalidate()
            await recs.invalidate()
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

    private func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let previous = persistence
        persistence = Task {
            await previous?.value
            await work()
        }
    }
}
