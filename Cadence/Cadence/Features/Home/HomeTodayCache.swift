import Foundation
import SwiftUI
import CadenceFeatures

/// Process-lifetime cache of Today's coach snapshot and suggested workout so
/// revisiting the tab shows the last result immediately instead of a spinner.
/// Entries are valid only for the same day and the same coach signature, so a
/// completed workout or a changed preference invalidates them.
@MainActor
enum HomeTodayCache {
    private static var snapshot: (key: Key, value: HomeCoachSnapshot)?
    private static var plan: (key: Key, value: EditablePlan)?

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

    static func cachedPlan(for key: Key) -> EditablePlan? {
        plan?.key == key ? plan?.value : nil
    }

    static func store(_ value: EditablePlan, for key: Key) {
        plan = (key, value)
    }
}

extension HomeView {
    var todayCacheKey: HomeTodayCache.Key { .init(signature: coachSignature, day: Self.dayString()) }

    func buildAndCacheCoachSnapshot() async -> HomeCoachSnapshot {
        let key = todayCacheKey
        let snapshot = await buildCoachSnapshot()
        HomeTodayCache.store(snapshot, for: key)
        return snapshot
    }
}
