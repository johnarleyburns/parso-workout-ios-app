import XCTest
@testable import CadenceCore

final class CardioMathTests: XCTestCase {

    func testHRZones() {
        XCTAssertEqual(CardioMath.hrZone(bpm: 100, maxHR: 200), 1) // 50%
        XCTAssertEqual(CardioMath.hrZone(bpm: 130, maxHR: 200), 2) // 65%
        XCTAssertEqual(CardioMath.hrZone(bpm: 150, maxHR: 200), 3) // 75%
        XCTAssertEqual(CardioMath.hrZone(bpm: 170, maxHR: 200), 4) // 85%
        XCTAssertEqual(CardioMath.hrZone(bpm: 190, maxHR: 200), 5) // 95%
    }

    func testHRZoneBoundaries() {
        XCTAssertEqual(CardioMath.hrZone(bpm: 120, maxHR: 200), 2) // exactly 60% → Z2
        XCTAssertEqual(CardioMath.hrZone(bpm: 0, maxHR: 200), 1)
        XCTAssertEqual(CardioMath.hrZone(bpm: 150, maxHR: 0), 1)
    }

    func testDefaultMaxHR() {
        XCTAssertEqual(CardioMath.defaultMaxHR(age: 30), 187, accuracy: 0.001) // 208 - 21
        XCTAssertEqual(CardioMath.defaultMaxHR(age: nil), 190)
    }

    func testPace() {
        // 1 km in 300 s → 300 s/km
        XCTAssertEqual(CardioMath.paceSecPerKm(distanceMeters: 1000, seconds: 300)!, 300, accuracy: 1e-6)
        XCTAssertNil(CardioMath.paceSecPerKm(distanceMeters: 0, seconds: 300))
        XCTAssertEqual(CardioMath.formatPace(secPerKm: 305), "5:05 /km")
        XCTAssertEqual(CardioMath.formatPace(secPerKm: nil), "—")
    }

    func testCaloriesMETFallback() {
        // running 30 min @75kg, no HR: 9.8 * 75 * 0.5 = 367.5
        let kcal = CardioMath.estimateCalories(type: .run, seconds: 1800, avgHR: nil, weightKg: 75)
        XCTAssertEqual(kcal, 367.5, accuracy: 0.5)
    }

    func testCaloriesHRBasedPositive() {
        let kcal = CardioMath.estimateCalories(type: .run, seconds: 1800, avgHR: 150, weightKg: 75)
        XCTAssertGreaterThan(kcal, 0)
    }
}
