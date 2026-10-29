import Foundation
import SwiftUI
import os
import CadenceCore
import CadenceFeatures

/// Today's recommendation cache. Two layers, both keyed on a deterministic
/// semantic fingerprint (never view identity or a `@State` UUID):
/// - a durable Application Support DTO (`TodayRecommendationCacheStore`) that
///   renders the hero immediately after an app relaunch, and
/// - an in-process full `HomeCoachSnapshot` so tab switches / view recreation
///   skip the coach pipeline entirely.
/// The ownership boundary lives in `TodayRecommendationCoordinator`: calls
/// from `.thisWeek` cannot write, restore-and-discard, or invalidate.
@MainActor
enum HomeTodayCache {
    private static let log = Logger(subsystem: "guru.parso.cadence", category: "TodayCache")

    static let coordinator: TodayRecommendationCoordinator<HomeCoachSnapshot> = {
        let c = TodayRecommendationCoordinator<HomeCoachSnapshot>(
            recommendationStore: TodayRecommendationCacheStore(
                fileURL: TodayRecommendationCacheStore.defaultFileURL()),
            suggestionStore: TodaySuggestedWorkoutCacheStore(
                fileURL: TodaySuggestedWorkoutCacheStore.defaultFileURL()))
        // Outcome names only; never workout content.
        c.outcomeObserver = { log.info("today cache outcome: \($0.rawValue, privacy: .public)") }
        c.invalidationObserver = { reason in
            log.info("today cache invalidation: \(reason.rawValue, privacy: .public)")
            signposter.emitEvent("cacheInvalidation", "\(reason.rawValue, privacy: .public)")
        }
        return c
    }()

    /// Launch-phase signposts (names only, never workout data).
    static let signposter = OSSignposter(subsystem: "guru.parso.cadence", category: "TodayLaunch")

    static var suggestionStore: TodaySuggestedWorkoutCacheStore { coordinator.suggestionStore }
}

extension HomeView.Surface {
    var cacheSurface: TodayCacheSurface { self == .today ? .today : .thisWeek }
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
        HomeTodayCache.coordinator.store(
            snapshot,
            payload: TodayRecommendationPayload(
                hero: TodayHeroPresenter.recommendation(snapshot.decision),
                primaryIsStrength: snapshot.decision.primary.kind == .strength),
            fingerprint: key.fingerprint, passiveStamp: key.passiveStamp,
            surface: surface.cacheSurface)
        return snapshot
    }

    /// Restores a valid cached recommendation without running the coach
    /// pipeline. Returns true when no recomputation is needed.
    func restoreTodayRecommendation() async -> Bool {
        await HomeTodayCache.coordinator.settle()
        let key = todayFingerprint
        let passive: String? = passiveSamplesLoaded ? key.passiveStamp : nil
        if let cached = HomeTodayCache.coordinator.cachedSnapshot(fingerprint: key.fingerprint, passiveStamp: passive) {
            coachSnapshot = cached
            coachSnapshotReady = true
            restoredRecommendation = nil
            return true
        }
        guard !coachSnapshotReady,
              let hit = await HomeTodayCache.coordinator.restoreProvisional(surface: surface.cacheSurface)
        else {
            restoredRecommendation = nil
            return false
        }
        // Hero renders from the durable DTO now, without waiting for SwiftData
        // or HealthKit inputs to settle; freshness is reconciled afterwards.
        restoredRecommendation = hit.payload
        return false
    }
}

extension HomeView {
    /// Coach task body: a valid cached recommendation (in-process or durable,
    /// even after relaunch) is shown before any loading state is set.
    func runCoachTask() async {
        await restoreTodayDisplayCacheImmediately()
        // Let the cached hero render before any SwiftData traversal below.
        await Task.yield()
        if await restoreTodayRecommendation() { return }
        if restoredRecommendation == nil {
            coachSnapshotReady = false
        } else {
            // Provisional hero stays visible while inputs settle: HealthKit
            // readiness loaded and the initial Health ingest finished, then a
            // quiet period with an unchanged fingerprint (a change restarts
            // this task via `coachSignature`). Bounded so it cannot hang.
            for _ in 0..<200 where !(passiveSamplesLoaded && coachInputsSettled) && !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard !Task.isCancelled else { return }
            let before = todayFingerprint
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            let key = todayFingerprint
            HomeTodayCache.signposter.emitEvent("stableInputsReady")
            guard key == before else { return await runCoachTask() }
            // Matching or not, the full snapshot still hydrates for the other
            // coach surfaces; a mismatch replaces the record via `store`.
            HomeTodayCache.coordinator.reconcileProvisional(
                stableFingerprint: key.fingerprint, stablePassiveStamp: key.passiveStamp,
                surface: surface.cacheSurface)
        }
        let signpost = HomeTodayCache.signposter
        let interval = signpost.beginInterval("fullSnapshot")
        await refreshCoachSnapshot()
        signpost.endInterval("fullSnapshot", interval)
        restoredRecommendation = nil
    }

    /// First-frame restore: reads only the small Application Support envelopes,
    /// validates schema/day and publishes DTO state. It never computes
    /// `todayFingerprint`, touches SwiftData, waits for HealthKit or builds a
    /// snapshot; freshness is reconciled afterwards by `runCoachTask` and
    /// `prepareTodaySuggestion`.
    func restoreTodayDisplayCacheImmediately() async {
        guard surface == .today else { return }
        if !coachSnapshotReady, restoredRecommendation == nil,
           let hit = await HomeTodayCache.coordinator.restoreProvisional(surface: .today) {
            restoredRecommendation = hit.payload
            HomeTodayCache.signposter.emitEvent("heroRestored")
        }
        if todaySuggestedPlan == nil, suggestedWorkoutPlan == nil,
           let hit = await HomeTodayCache.suggestionStore.peekDisplayable() {
            guard todaySuggestedPlan == nil, suggestedWorkoutPlan == nil else { return }
            todaySuggestedPlan = hit.plan.makePlan()
            todaySuggestionRenderedKey = hit.earlyKey
            HomeTodayCache.signposter.emitEvent("suggestionRestored")
        }
    }

    /// Unchanged HealthKit readiness keeps the cached result; the relaunch
    /// hydration in `runCoachTask` already waits for these samples.
    func handlePassiveSamplesChanged() {
        guard coachSnapshotReady || restoredRecommendation == nil else { return }
        Task {
            let key = todayFingerprint
            if coachSnapshotReady,
               HomeTodayCache.coordinator.cachedSnapshot(fingerprint: key.fingerprint,
                                             passiveStamp: key.passiveStamp) != nil { return }
            await refreshCoachSnapshot()
        }
    }
}
