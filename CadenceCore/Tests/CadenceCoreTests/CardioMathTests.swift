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

    // MARK: - VO2max estimation

    func testCooperVO2max() {
        let vo2 = CardioMath.cooperVO2max(distanceMeters: 2400)
        XCTAssertEqual(vo2, 42.35, accuracy: 0.1)
    }

    func testCooperVO2maxZeroDistance() {
        let vo2 = CardioMath.cooperVO2max(distanceMeters: 0)
        XCTAssertLessThan(vo2, 0)
    }

    func testRun1_5mileVO2max() {
        let vo2 = CardioMath.run1_5mileVO2max(timeSeconds: 720)
        XCTAssertEqual(vo2, 43.75, accuracy: 0.1)
    }

    func testRun1_5mileVO2maxZeroTime() {
        let vo2 = CardioMath.run1_5mileVO2max(timeSeconds: 0)
        XCTAssertEqual(vo2, 0)
    }

    func testRockportVO2max() {
        let vo2 = CardioMath.rockportVO2max(weightKg: 70, ageYears: 30,
                                            sexCode: 1, walkTimeSeconds: 840,
                                            endingHR: 140)
        XCTAssertGreaterThan(vo2, 20)
        XCTAssertLessThan(vo2, 80)
    }

    func testQueensCollegeVO2maxMale() {
        let vo2 = CardioMath.queensCollegeVO2max(recoveryHR: 140, sexCode: 1)
        XCTAssertEqual(vo2, 52.53, accuracy: 0.1)
    }

    func testQueensCollegeVO2maxFemale() {
        let vo2 = CardioMath.queensCollegeVO2max(recoveryHR: 140, sexCode: 0)
        XCTAssertEqual(vo2, 39.952, accuracy: 0.1)
    }

    // MARK: - Fitness category

    func testFitnessCategoryYoungMaleGood() {
        let cat = CardioMath.fitnessCategory(vo2max: 46.0, ageYears: 25, sexCode: 1)
        XCTAssertEqual(cat, .good)
    }

    func testFitnessCategoryOlderFemaleSuperior() {
        let cat = CardioMath.fitnessCategory(vo2max: 50.0, ageYears: 25, sexCode: 0)
        XCTAssertEqual(cat, .superior)
    }

    func testFitnessCategoryVeryPoor() {
        let cat = CardioMath.fitnessCategory(vo2max: 15.0, ageYears: 40, sexCode: 1)
        XCTAssertEqual(cat, .veryPoor)
    }
}
