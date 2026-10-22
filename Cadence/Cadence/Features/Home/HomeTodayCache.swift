import Foundation
import SwiftUI
import CadenceCore
import CadenceFeatures

/// Today's recommendation cache. Two layers, both keyed on a deterministic
/// semantic fingerprint (never view identity or a `@State` UUID):
/// - a durable Application Support DTO (`TodayRecommendationCacheStore`) that
///   renders the hero immediately after an app relaunch, and
/// - an in-process full `HomeCoachSnapshot` so tab switches / view recreation
///   skip the coach pipeline entirely.
/// This Week never writes here, so it cannot evict Today.
@MainActor
enum HomeTodayCache {
    private static var snapshot: (fingerprint: String, passiveStamp: String, value: HomeCoachSnapshot)?
    private static var pendingInvalidation: Task<Void, Never>?

    /// Durable same-local-day Today suggestion cache (see `TodaySuggestedWorkoutCacheStore`).
    static let suggestionStore = TodaySuggestedWorkoutCacheStore(
        fileURL: TodaySuggestedWorkoutCacheStore.defaultFileURL())
    static let recommendationStore = TodayRecommendationCacheStore(
        fileURL: TodayRecommendationCacheStore.defaultFileURL())

    /// In-process hit. `passiveStamp == nil` = HealthKit readiness not loaded yet.
    static func cachedSnapshot(fingerprint: String, passiveStamp: String?) -> HomeCoachSnapshot? {
        guard let snapshot, snapshot.fingerprint == fingerprint,
              passiveStamp == nil || snapshot.passiveStamp == passiveStamp else { return nil }
        return snapshot.value
    }

    static func store(_ value: HomeCoachSnapshot, fingerprint: String, passiveStamp: String) {
        snapshot = (fingerprint, passiveStamp, value)
        let payload = TodayRecommendationPayload(
            hero: TodayHeroPresenter.recommendation(value.decision),
            primaryIsStrength: value.decision.primary.kind == .strength)
        let store = recommendationStore
        Task { await store.save(payload, fingerprint: fingerprint, passiveStamp: passiveStamp) }
    }

    /// Single invalidation point for history / preference / readiness changes
    /// (workout complete, import, edit, delete, HealthKit and CloudKit refresh).
    static func invalidate() {
        snapshot = nil
        let plans = suggestionStore, recs = recommendationStore
        let previous = pendingInvalidation
        pendingInvalidation = Task {
            await previous?.value
            await plans.invalidate()
            await recs.invalidate()
        }
    }

    /// Lets a just-requested invalidation reach disk before a restore reads it.
    static func settleInvalidation() async { await pendingInvalidation?.value }

    static func restoreDurable(fingerprint: String, passiveStamp: String?)
        async -> (payload: TodayRecommendationPayload, passiveStamp: String)? {
        await settleInvalidation()
        return await recommendationStore.restore(fingerprint: fingerprint, passiveStamp: passiveStamp)
    }
}

extension HomeView {
    /// Fingerprint of the real coaching inputs; excludes `historyRefreshToken`.
    var todayFingerprint: TodayRecommendationFingerprint.Result {
        func stamp<T>(_ items: [T], id: (T) -> UUID, changed: (T) -> Date?) -> String {
            TodayRecommendationFingerprint.historyStamp(
                count: items.count, latestChange: items.compactMap(changed).max(), ids: items.map(id))
        }
        return TodayRecommendationFingerprint.make(
            dayKey: Self.dayString() + "@" + TimeZone.current.identifier,
            sessionsStamp: stamp(sessions, id: \.id, changed: \.updatedAt),
            cardioStamp: stamp(cardio, id: \.id, changed: \.updatedAt),
            assessmentsStamp: stamp(assessments, id: \.id, changed: \.updatedAt),
            readinessStamp: stamp(readinessEntries, id: \.id, changed: \.updatedAt),
            painToday: HomeCoachModel.painToday(readiness: readinessEntries),
            goal: settings.trainingGoal,
            experience: settings.experienceLevel,
            formula: settings.formula,
            schedule: settings.coachSchedulePreferences,
            profile: settings.coachPreferenceProfile,
            userAge: settings.userAge,
            cardioMaximumHROverride: settings.cardioMaximumHROverride,
            overrideWeekKey: settings.coachPlanOverrideWeekKey,
            passiveSamples: passiveSamples)
    }

    func buildAndCacheCoachSnapshot() async -> HomeCoachSnapshot {
        let key = todayFingerprint
        let snapshot = await buildCoachSnapshot()
        HomeTodayCache.store(snapshot, fingerprint: key.fingerprint, passiveStamp: key.passiveStamp)
        return snapshot
    }

    /// Restores a valid cached recommendation without running the coach
    /// pipeline. Returns true when no recomputation is needed.
    func restoreTodayRecommendation() async -> Bool {
        await HomeTodayCache.settleInvalidation()
        let key = todayFingerprint
        let passive: String? = passiveSamplesLoaded ? key.passiveStamp : nil
        if let cached = HomeTodayCache.cachedSnapshot(fingerprint: key.fingerprint, passiveStamp: passive) {
            coachSnapshot = cached
            coachSnapshotReady = true
            restoredRecommendation = nil
            return true
        }
        guard !coachSnapshotReady,
              let hit = await HomeTodayCache.restoreDurable(fingerprint: key.fingerprint, passiveStamp: passive)
        else {
            restoredRecommendation = nil
            return false
        }
        // Hero renders from the durable DTO now; the full snapshot hydrates
        // for the other coach surfaces behind it without a loading state.
        restoredRecommendation = hit.payload
        return false
    }
}

extension HomeView {
    /// Coach task body: a valid cached recommendation (in-process or durable,
    /// even after relaunch) is shown before any loading state is set.
    func runCoachTask() async {
        if await restoreTodayRecommendation() { return }
        if restoredRecommendation == nil {
            coachSnapshotReady = false
        } else {
            // Hydrate once with the real HealthKit inputs so the hero does not
            // flip when readiness samples arrive.
            for _ in 0..<100 where !passiveSamplesLoaded && !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard !Task.isCancelled else { return }
        }
        await refreshCoachSnapshot()
        restoredRecommendation = nil
    }

    /// Unchanged HealthKit readiness keeps the cached result; the relaunch
    /// hydration in `runCoachTask` already waits for these samples.
    func handlePassiveSamplesChanged() {
        guard coachSnapshotReady || restoredRecommendation == nil else { return }
        Task {
            let key = todayFingerprint
            if coachSnapshotReady,
               HomeTodayCache.cachedSnapshot(fingerprint: key.fingerprint,
                                             passiveStamp: key.passiveStamp) != nil { return }
            await refreshCoachSnapshot()
        }
    }
}
