import Foundation

/// A Watch-local strength or cardio completion the phone has not yet
/// acknowledged. Added immediately so This Week reflects a disconnected
/// completion, and removed only by a matching phone acknowledgement — never
/// by a new baseline arriving, so a slow reconnect cannot flash to zero or
/// double count. Identity is the completion's own stable ID (the strength
/// `completion_id` / cardio `WatchCardioCompletion.id`), never a random UI UUID.
public struct WatchWeekLocalOverlay: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable { case strength, cardio }

    public let id: UUID
    /// `AppSettings.weekKey(for:)` of `completedAt`; identifies the overlay's week
    /// without re-deriving week boundaries on the Watch.
    public let weekKey: String
    public let kind: Kind
    public let sets: Double
    public let moderateEquivalentMinutes: Double
    public let completedAt: Date

    public init(id: UUID, weekKey: String, kind: Kind,
                sets: Double = 0, moderateEquivalentMinutes: Double = 0,
                completedAt: Date) {
        self.id = id
        self.weekKey = weekKey
        self.kind = kind
        self.sets = max(0, sets)
        self.moderateEquivalentMinutes = max(0, moderateEquivalentMinutes)
        self.completedAt = completedAt
    }
}

/// Watch `UserDefaults`-backed durable store for unresolved local overlays.
/// Survives relaunch; malformed persisted data decodes as empty rather than
/// crashing the Watch launcher.
public final class WatchWeekLocalOverlayStore {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "watch.week.localOverlays.v1") {
        self.defaults = defaults
        self.key = key
    }

    private func loadAll() -> [WatchWeekLocalOverlay] {
        guard let data = defaults.data(forKey: key),
              let values = try? JSONDecoder().decode([WatchWeekLocalOverlay].self, from: data) else { return [] }
        return values
    }

    private func saveAll(_ overlays: [WatchWeekLocalOverlay]) {
        guard let data = try? JSONEncoder().encode(overlays) else { return }
        defaults.set(data, forKey: key)
    }

    public func overlays(forWeekKey weekKey: String) -> [WatchWeekLocalOverlay] {
        loadAll().filter { $0.weekKey == weekKey }
    }

    /// Same ID replaces (never duplicates) so a retried completion stays represented once.
    public func record(_ overlay: WatchWeekLocalOverlay) {
        var all = loadAll()
        all.removeAll { $0.id == overlay.id }
        all.append(overlay)
        saveAll(all)
    }

    /// Idempotent: acknowledging an already-removed or unknown ID is a no-op.
    public func acknowledge(id: UUID) {
        var all = loadAll()
        let before = all.count
        all.removeAll { $0.id == id }
        guard all.count != before else { return }
        saveAll(all)
    }

    public func prune(keepingWeekKeys: Set<String>) {
        saveAll(loadAll().filter { keepingWeekKeys.contains($0.weekKey) })
    }
}
