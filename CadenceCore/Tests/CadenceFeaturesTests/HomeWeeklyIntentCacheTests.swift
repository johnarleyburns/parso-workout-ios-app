import XCTest
import CadenceCore
@testable import CadenceFeatures

final class HomeWeeklyIntentCacheTests: XCTestCase {
    private func url() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("weekly-intent-\(UUID().uuidString).json")
    }
    private func snapshot(_ week: String = "2026-11-09") -> HomeWeeklyIntentSnapshot {
        HomeWeeklyIntentSnapshot(weekKey: week, setsByMuscle: ["chest": 9],
                                 cardio: .init(actualMinutes: 30, belowModerateMinutes: 0,
                                               moderateMinutes: 30, vigorousMinutes: 0,
                                               moderateEquivalentMinutes: 30, unclassifiedMinutes: 0,
                                               zoneMinutes: [:], algorithmVersion: .hrrGuidelineV1))
    }

    func testPeekNilThenRoundTripAndOverwrite() async {
        let u = url(); defer { try? FileManager.default.removeItem(at: u) }
        let store = HomeWeeklyIntentCacheStore(fileURL: u)
        let empty = await store.peek()
        XCTAssertNil(empty)
        await store.save(snapshot())
        let first = await store.peek()
        XCTAssertEqual(first, snapshot())
        await store.save(snapshot("2026-11-16"))
        let second = await store.peek()
        XCTAssertEqual(second?.weekKey, "2026-11-16")
    }

    func testFreshInstanceReadsPriorWrite() async {
        let u = url(); defer { try? FileManager.default.removeItem(at: u) }
        await HomeWeeklyIntentCacheStore(fileURL: u).save(snapshot())
        let back = await HomeWeeklyIntentCacheStore(fileURL: u).peek()
        XCTAssertEqual(back, snapshot())
    }

    func testNilFileURLStaysMemoryOnly() async {
        let store = HomeWeeklyIntentCacheStore(fileURL: nil)
        await store.save(snapshot())
        let back = await store.peek()
        XCTAssertEqual(back, snapshot())
    }
}
