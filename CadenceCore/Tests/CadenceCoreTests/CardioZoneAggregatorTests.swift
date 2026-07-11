import XCTest
@testable import CadenceCore

/// P7 (issue 7) — weekly HR-zone aggregation, tonnage formatting, and the
/// completed strength+cardio day label fix.
final class CardioZoneAggregatorTests: XCTestCase {

    func testEstimatedZoneFromModalityWhenNoHR() {
        // Easy walk → Z1; easy run → Z2; moderate → Z3; vigorous → Z4.
        let walk = CardioZoneAggregator.Session(modality: .walk, intensity: .easy, durationMinutes: 30)
        let run = CardioZoneAggregator.Session(modality: .run, intensity: .easy, durationMinutes: 30)
        let mod = CardioZoneAggregator.Session(modality: .cycle, intensity: .moderate, durationMinutes: 40)
        let hard = CardioZoneAggregator.Session(modality: .run, intensity: .vigorous, durationMinutes: 20)
        let z = CardioZoneAggregator.weeklyZoneMinutes(sessions: [walk, run, mod, hard], age: 40)
        XCTAssertEqual(z[1] ?? 0, 30, accuracy: 0.001)
        XCTAssertEqual(z[2] ?? 0, 30, accuracy: 0.001)
        XCTAssertEqual(z[3] ?? 0, 40, accuracy: 0.001)
        XCTAssertEqual(z[4] ?? 0, 20, accuracy: 0.001)
    }

    func testZoneMinutesFromHRSamples() {
        // A 10-min session; first 5 min at 120 bpm, last 5 at 170 bpm. Age 30 →
        // HRmax ≈ 187. 120/187 ≈ 64% → Z2; 170/187 ≈ 91% → Z5.
        let samples = [
            CardioZoneAggregator.HRPoint(t: 0, bpm: 120),
            CardioZoneAggregator.HRPoint(t: 300, bpm: 170),
        ]
        let session = CardioZoneAggregator.Session(modality: .run, intensity: .moderate,
                                                   durationMinutes: 10, hrSamples: samples)
        let z = CardioZoneAggregator.weeklyZoneMinutes(sessions: [session], age: 30)
        XCTAssertEqual(z[2] ?? 0, 5, accuracy: 0.001)
        XCTAssertEqual(z[5] ?? 0, 5, accuracy: 0.001)
    }

    func testEmptyAndZeroDurationIgnored() {
        let empty = CardioZoneAggregator.Session(modality: .run, intensity: .easy, durationMinutes: 0)
        XCTAssertTrue(CardioZoneAggregator.weeklyZoneMinutes(sessions: [empty], age: 40).isEmpty)
        XCTAssertTrue(CardioZoneAggregator.weeklyZoneMinutes(sessions: [], age: nil).isEmpty)
    }

    // MARK: tonnage

    func testTonnageKgAndPounds() {
        // 12,400 kg = 12.4 t; in pounds = 27,337 lb ≈ 13.7 tn.
        XCTAssertEqual(WorkoutMath.tonnageLabel(volumeKg: 12_400, unit: .kilograms), "12.4 t")
        let lbLabel = WorkoutMath.tonnageLabel(volumeKg: 12_400, unit: .pounds)
        XCTAssertTrue(lbLabel.hasSuffix(" tn"), "US tons suffix, got \(lbLabel)")
    }

    func testTonnageWholeNumberTrims() {
        XCTAssertEqual(WorkoutMath.tonnageLabel(volumeKg: 10_000, unit: .kilograms), "10 t")
    }

    // MARK: HRmax public + Tanaka

    func testDefaultMaxHRPublicTanaka() {
        XCTAssertEqual(CardioMath.defaultMaxHR(age: 30), 208 - 0.7 * 30, accuracy: 0.001)
        XCTAssertEqual(CardioMath.defaultMaxHR(age: nil), 190, accuracy: 0.001)
    }
}
