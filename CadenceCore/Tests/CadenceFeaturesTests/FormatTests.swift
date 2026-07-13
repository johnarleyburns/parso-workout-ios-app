import XCTest
import CadenceCore
import CadenceFeatures

final class FormatTests: XCTestCase {
    func testWeightKilograms() {
        XCTAssertEqual(Format.weight(100, unit: .kilograms, decimals: 0), "100 kg")
    }

    func testWeightValueNoUnit() {
        XCTAssertEqual(Format.weightValue(60, unit: .kilograms, decimals: 0), "60")
    }

    func testPreviousShort() {
        XCTAssertEqual(Format.previousShort(60, reps: 8, unit: .kilograms), "60×8")
    }

    func testDuration() {
        XCTAssertEqual(Format.duration(90), "1:30")
        XCTAssertEqual(Format.duration(3661), "1:01:01")
        XCTAssertEqual(Format.duration(0), "0:00")
    }

    func testClock() {
        XCTAssertEqual(Format.clock(90), "1:30")
        XCTAssertEqual(Format.clock(5), "0:05")
    }

    func testDistance() {
        XCTAssertEqual(Format.distance(1500), "1.50 km")
        XCTAssertEqual(Format.distance(500), "500 m")
    }

    func testHeartRate() {
        XCTAssertEqual(Format.heartRate(nil), "—")
        XCTAssertEqual(Format.heartRate(180), "180 bpm")
    }

    func testRxLoadPounds() {
        XCTAssertEqual(Format.rxLoad(male: 95, female: 65, unit: .pounds), "95/65 lb")
        XCTAssertEqual(Format.rxLoad(male: 95, female: nil, unit: .pounds), "95 lb")
        XCTAssertEqual(Format.rxLoad(male: 95, female: 95, unit: .pounds), "95 lb")
        XCTAssertNil(Format.rxLoad(male: nil, female: 65, unit: .pounds))
    }

    func testRxLoadKilogramsAddsConversion() {
        XCTAssertEqual(Format.rxLoad(male: 95, female: 65, unit: .kilograms), "95/65 lb (43/29 kg)")
    }
}
