import XCTest
import SwiftData
import CadenceCore
import CadenceFeatures

@MainActor
final class YourWeekPresenterTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let container = try CadenceStore.makeModelContainer(inMemory: true)
        return ModelContext(container)
    }

    func testModalityMapping() {
        XCTAssertEqual(YourWeekPresenter.modality(for: .run), .run)
        XCTAssertEqual(YourWeekPresenter.modality(for: .walk), .walk)
        XCTAssertEqual(YourWeekPresenter.modality(for: .cycle), .cycle)
        XCTAssertEqual(YourWeekPresenter.modality(for: .boxing), .boxing)
    }

    func testIntensityFromHeartRate() throws {
        let ctx = try makeContext()
        let start = Date()
        func cardio(avg: Double) -> CardioWorkout {
            let c = CardioWorkout(type: .run, start: start, end: start.addingTimeInterval(1800),
                                  avgHeartRate: avg, source: .iphone)
            ctx.insert(c); return c
        }
        // age nil → defaultMaxHR ~190. 100/190≈.53 easy, 135/190≈.71 moderate, 165/190≈.87 vigorous.
        XCTAssertEqual(YourWeekPresenter.intensity(for: cardio(avg: 100), age: nil), .easy)
        XCTAssertEqual(YourWeekPresenter.intensity(for: cardio(avg: 135), age: nil), .moderate)
        XCTAssertEqual(YourWeekPresenter.intensity(for: cardio(avg: 165), age: nil), .vigorous)
    }

    func testIntensityFallsBackToModalityWithoutHR() throws {
        let ctx = try makeContext()
        let start = Date()
        let box = CardioWorkout(type: .boxing, start: start, end: start.addingTimeInterval(1800), source: .iphone)
        let walk = CardioWorkout(type: .walk, start: start, end: start.addingTimeInterval(1800), source: .iphone)
        ctx.insert(box); ctx.insert(walk)
        XCTAssertEqual(YourWeekPresenter.intensity(for: box, age: nil), .vigorous)
        XCTAssertEqual(YourWeekPresenter.intensity(for: walk, age: nil), .easy)
    }

    func testWeeklyZoneMinutesExcludesBeforeWindow() throws {
        let ctx = try makeContext()
        let now = Date()
        let weekStart = now.addingTimeInterval(-3 * 86_400)
        let inWeek = CardioWorkout(type: .run, start: now.addingTimeInterval(-1 * 86_400),
                                   end: now.addingTimeInterval(-1 * 86_400 + 1800),
                                   avgHeartRate: 140, source: .iphone)
        let old = CardioWorkout(type: .run, start: now.addingTimeInterval(-10 * 86_400),
                                end: now.addingTimeInterval(-10 * 86_400 + 1800),
                                avgHeartRate: 140, source: .iphone)
        ctx.insert(inWeek); ctx.insert(old)
        let zones = YourWeekPresenter.weeklyZoneMinutes(cardio: [inWeek, old], since: weekStart, age: 30)
        let total = zones.values.reduce(0, +)
        // Only the in-week 30-min workout should contribute (~30 minutes total).
        XCTAssertGreaterThan(total, 0)
        XCTAssertLessThanOrEqual(total, 31)
    }

    func testZoneRowsFiltersTinyValues() {
        let rows = YourWeekPresenter.zoneRows([1: 10.0, 2: 0.2, 3: 5.0])
        XCTAssertEqual(rows.map(\.zone), [1, 3])
    }
}
