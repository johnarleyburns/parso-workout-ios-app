import Foundation
import CadenceCore
import CadenceFeatures

/// Content key for the Home activity/muscle-coverage projection. Unlike
/// `HomeActivityTaskIdentity` (which exists only to decide when a single
/// `HomeView` instance's `.task` should restart), this key deliberately
/// excludes `historyRefreshToken` — a random `UUID()` each `HomeView`
/// instance bumps independently — so that Today and This Week, which read
/// the same underlying SwiftData history, always compute an *equal* key for
/// *equal* content and can therefore share one cache entry.
struct HomeActivityCacheKey: Equatable {
    let sessionsStamp: String
    let cardioStamp: String
    let scheduledWorkouts: [ScheduledWorkoutTaskSignature]
    let passiveSamples: [PassiveReadinessSample]
    let userAge: Int?
    let maximumHROverride: Double?
    /// The projection is relative to "now"; a new day or week must recompute.
    let dayStart: Date
    let weekStart: Date
}

extension HomeView {
    var activityCacheKey: HomeActivityCacheKey {
        let now = Date()
        return HomeActivityCacheKey(
            sessionsStamp: TodayRecommendationFingerprint.historyStamp(
                count: sessions.count, latestChange: sessions.compactMap(\.updatedAt).max(),
                ids: sessions.map(\.id)),
            cardioStamp: TodayRecommendationFingerprint.historyStamp(
                count: cardio.count, latestChange: cardio.compactMap(\.updatedAt).max(),
                ids: cardio.map(\.id)),
            scheduledWorkouts: scheduledWorkoutTaskSignatures,
            passiveSamples: passiveSamples,
            userAge: settings.userAge,
            maximumHROverride: settings.cardioMaximumHROverride,
            dayStart: Calendar.current.startOfDay(for: now),
            weekStart: WeeklyStats.weekStart(now: now))
    }
}

/// In-process cache for the Home activity/muscle-coverage projection, shared
/// across the Today and This Week surfaces via one process-wide instance —
/// deliberately the mirror image of `TodayRecommendationCoordinator`'s
/// surface-ownership boundary: there is no durable record here for a second
/// surface to corrupt, so both surfaces may freely read and write it. Fixes
/// "Loading this week's muscle coverage…" reappearing on every tab switch
/// after the identical projection was already computed once.
@MainActor
enum HomeActivityCache {
    static let shared = ContentKeyedCache<HomeActivityCacheKey, HomeView.HomeActivityProjection>()
}
