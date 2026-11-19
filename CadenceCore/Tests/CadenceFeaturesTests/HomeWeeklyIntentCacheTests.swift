import Foundation
import Testing
import CadenceCore
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures
import CadencePhoneFeatures

struct HomeWeeklyIntentCacheTests {
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

    @Test func peekNilThenRoundTripAndOverwrite() async {
        let u = url(); defer { try? FileManager.default.removeItem(at: u) }
        let store = HomeWeeklyIntentCacheStore(fileURL: u)
        let empty = await store.peek()
        #expect(empty == nil)
        await store.save(snapshot())
        let first = await store.peek()
        #expect(first == snapshot())
        await store.save(snapshot("2026-11-16"))
        let second = await store.peek()
        #expect(second?.weekKey == "2026-11-16")
    }

    @Test func freshInstanceReadsPriorWrite() async {
        let u = url(); defer { try? FileManager.default.removeItem(at: u) }
        await HomeWeeklyIntentCacheStore(fileURL: u).save(snapshot())
        let back = await HomeWeeklyIntentCacheStore(fileURL: u).peek()
        #expect(back == snapshot())
    }

    @Test func nilFileURLStaysMemoryOnly() async {
        let store = HomeWeeklyIntentCacheStore(fileURL: nil)
        await store.save(snapshot())
        let back = await store.peek()
        #expect(back == snapshot())
    }
}
