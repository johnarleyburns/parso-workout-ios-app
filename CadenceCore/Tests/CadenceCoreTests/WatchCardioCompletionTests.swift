import XCTest
@testable import CadenceCore

final class WatchCardioCompletionTests: XCTestCase {
    func testRoundTripPreservesVersionedCompletion() throws {
        let id = UUID()
        let value = WatchCardioCompletion(id: id, type: .run, title: "Morning run",
                                          start: Date(timeIntervalSince1970: 100),
                                          end: Date(timeIntervalSince1970: 200),
                                          distanceMeters: 5000,
                                          hrSamples: [HRSamplePoint(t: 2, bpm: 140)],
                                          avgHeartRate: 135, maxHeartRate: 160,
                                          gpsEnabled: true)
        XCTAssertEqual(try WatchCardioCompletion.decode(value.encoded()), value)
    }

    func testUnsupportedVersionIsRejected() throws {
        let value = WatchCardioCompletion(type: .walk, start: Date(), end: Date(), version: 99)
        XCTAssertThrowsError(try WatchCardioCompletion.decode(value.encoded())) { error in
            XCTAssertEqual(error as? WatchCardioCompletion.DecodeError, .unsupportedVersion(99))
        }
    }

    func testNonGPSDistanceIsRemovedFromEnvelope() {
        let value = WatchCardioCompletion(type: .cycle, start: Date(), end: Date(),
                                          distanceMeters: 1000, gpsEnabled: false)
        XCTAssertNil(value.distanceMeters)
    }
    func testPoolSwimPreservesDistanceLapsAndPoolSizeWithoutGPS() throws {
        let value = WatchCardioCompletion(type: .swim, start: Date(), end: Date(),
            distanceMeters: 500, gpsEnabled: false, swimmingLapCount: 20, poolLengthMeters: 25)
        XCTAssertEqual(try WatchCardioCompletion.decode(value.encoded()), value)
        XCTAssertEqual(value.distanceMeters, 500)
        XCTAssertEqual(value.ingestedWorkout.distanceMeters, 500)
        XCTAssertEqual(value.swimmingLapCount, 20)
        XCTAssertEqual(value.poolLengthMeters, 25)
        XCTAssertFalse(value.gpsEnabled)
    }

    func testLegacyCompletionStillDecodesWithoutSwimmingFields() throws {
        let value = WatchCardioCompletion(type: .swim, start: Date(), end: Date())
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: value.encoded()) as? [String: Any])
        json.removeValue(forKey: "swimmingLapCount")
        json.removeValue(forKey: "poolLengthMeters")
        let decoded = try WatchCardioCompletion.decode(JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(decoded.swimmingLapCount)
        XCTAssertNil(decoded.poolLengthMeters)
    }

}
