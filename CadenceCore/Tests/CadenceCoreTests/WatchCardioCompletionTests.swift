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
}
