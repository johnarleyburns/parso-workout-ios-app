import XCTest
@testable import CadenceFeatures

@MainActor
final class ContentKeyedCacheTests: XCTestCase {
    func testMatchingKeyReturnsStoredValue() {
        let cache = ContentKeyedCache<Int, String>()
        cache.store("a", for: 1)
        XCTAssertEqual(cache.cached(for: 1), "a")
    }

    func testMismatchedKeyReturnsNil() {
        let cache = ContentKeyedCache<Int, String>()
        cache.store("a", for: 1)
        XCTAssertNil(cache.cached(for: 2))
    }

    func testNewerStoreEvictsThePreviousKey() {
        let cache = ContentKeyedCache<Int, String>()
        cache.store("a", for: 1)
        cache.store("b", for: 2)
        XCTAssertNil(cache.cached(for: 1), "a single-entry cache keeps only the latest write")
        XCTAssertEqual(cache.cached(for: 2), "b")
    }

    func testEmptyCacheReturnsNil() {
        XCTAssertNil(ContentKeyedCache<Int, String>().cached(for: 1))
    }
}
