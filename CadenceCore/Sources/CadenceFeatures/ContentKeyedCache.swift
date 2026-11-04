import Foundation

/// A single-entry, content-keyed, in-process memoization cache. Storing under
/// a key overwrites any previous entry; reading with a non-matching key
/// returns `nil` rather than a stale value — correctness falls out of using a
/// key that actually changes whenever the underlying content does, with no
/// separate invalidation call needed. No disk persistence and no eviction
/// policy beyond "newest write wins"; a caller that needs durability or
/// multiple entries needs a dedicated store instead (see
/// `TodayRecommendationCacheStore`).
@MainActor
public final class ContentKeyedCache<Key: Equatable, Value> {
    private var entry: (key: Key, value: Value)?

    public init() {}

    public func cached(for key: Key) -> Value? {
        entry?.key == key ? entry?.value : nil
    }

    public func store(_ value: Value, for key: Key) {
        entry = (key, value)
    }
}
