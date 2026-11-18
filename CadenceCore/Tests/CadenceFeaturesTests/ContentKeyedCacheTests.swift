import Testing
import Foundation
import CadencePhoneFeatures
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

@MainActor
@Suite final class ContentKeyedCacheTests {
    @Test func matchingKeyReturnsStoredValue() {
        let cache = ContentKeyedCache<Int, String>()
        cache.store("a", for: 1)
        #expect(cache.cached(for: 1) == "a")
    }

    @Test func mismatchedKeyReturnsNil() {
        let cache = ContentKeyedCache<Int, String>()
        cache.store("a", for: 1)
        #expect(cache.cached(for: 2) == nil)
    }

    @Test func newerStoreEvictsThePreviousKey() {
        let cache = ContentKeyedCache<Int, String>()
        cache.store("a", for: 1)
        cache.store("b", for: 2)
        #expect(cache.cached(for: 1) == nil, "a single-entry cache keeps only the latest write")
        #expect(cache.cached(for: 2) == "b")
    }

    @Test func emptyCacheReturnsNil() {
        #expect(ContentKeyedCache<Int, String>().cached(for: 1) == nil)
    }
}
