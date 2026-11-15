import Foundation
import SwiftUI
import os
import CadenceCore
import CadenceFeatures

/// Independent, fingerprint-free disk cache of the weekly rings snapshot.
@MainActor
enum HomeWeeklyIntentCache {
    static let store = HomeWeeklyIntentCacheStore(fileURL: HomeWeeklyIntentCacheStore.defaultFileURL())
}

@MainActor
enum HomeTodayCache {
    static let suggestionStore = TodaySuggestedWorkoutCacheStore(
        storage: TodaySuggestionCacheStorage.default(),
        outcomeObserver: { outcome in
            // Outcome names only; never plan content, ids, paths or keys.
            Self.log.info("today suggestion cache outcome: \(outcome.rawValue, privacy: .public)")
            Self.signposter.emitEvent("suggestionCache", "\(outcome.rawValue, privacy: .public)")
        })
    private nonisolated static let log = Logger(subsystem: "guru.parso.cadence", category: "TodayCache")
    nonisolated static let signposter = OSSignposter(subsystem: "guru.parso.cadence", category: "TodayLaunch")
}

extension HomeView {
    /// First-frame restore: a previously explicitly-requested, same-day plan
    /// (from #718/#719) is shown again without re-requesting. Nothing before
    /// any request ever existed is restored.
    func restoreTodayDisplayCacheImmediately() async {
        guard surface == .today else { return }
        if weeklyIntent == nil, let restored = await HomeWeeklyIntentCache.store.peek() {
            weeklyIntent = restored
        }
        if todaySuggestedPlan == nil, suggestedWorkoutPlan == nil,
           let hit = await HomeTodayCache.suggestionStore.peekDisplayable() {
            guard todaySuggestedPlan == nil, suggestedWorkoutPlan == nil else { return }
            todaySuggestedPlan = hit.plan.makePlan()
            todaySuggestionIsStartupFallback = false
            todaySuggestionRenderedKey = hit.earlyKey
            HomeTodayCache.signposter.emitEvent("suggestionRestored")
        }
    }
}
