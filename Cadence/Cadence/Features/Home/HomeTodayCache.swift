import Foundation
import SwiftUI
import CadenceFeatures

/// Process-lifetime cache of Today's coach snapshot so
/// revisiting the tab shows the last result immediately instead of a spinner.
/// Entries are valid only for the same day and the same coach signature, so a
/// completed workout or a changed preference invalidates them.
@MainActor
enum HomeTodayCache {
    private static var snapshot: (key: Key, value: HomeCoachSnapshot)?
    /// Process-wide history revision shared by every `HomeView` identity, so
    /// recreating a view (or opening This Week) never changes the cache key.
    /// Only a real invalidation (workout saved, ingest, day change) replaces it.
    static var revision = UUID()

    static func invalidate() {
        revision = UUID()
        snapshot = nil
    }
    /// Durable same-local-day Today suggestion cache (see `TodaySuggestedWorkoutCacheStore`).
    static let suggestionStore = TodaySuggestedWorkoutCacheStore(
        fileURL: TodaySuggestedWorkoutCacheStore.defaultFileURL())

    struct Key: Equatable {
        let signature: HomeCoachModel.Signature
        let day: String
    }

    static func cachedSnapshot(for key: Key) -> HomeCoachSnapshot? {
        snapshot?.key == key ? snapshot?.value : nil
    }

    static func store(_ value: HomeCoachSnapshot, for key: Key) {
        snapshot = (key, value)
    }
}

extension HomeView {
    var todayCacheKey: HomeTodayCache.Key { .init(signature: coachSignature, day: Self.dayString()) }

    func buildAndCacheCoachSnapshot() async -> HomeCoachSnapshot {
        let key = todayCacheKey
        let snapshot = await buildCoachSnapshot()
        // Only Today owns the cache; This Week must not evict its entry.
        if surface == .today { HomeTodayCache.store(snapshot, for: key) }
        return snapshot
    }
}
