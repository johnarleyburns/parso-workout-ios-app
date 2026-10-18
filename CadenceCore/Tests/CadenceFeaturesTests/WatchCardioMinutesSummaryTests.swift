import XCTest
import CadenceCore
@testable import CadenceFeatures

final class WatchCardioMinutesSummaryTests: XCTestCase {
    func testSplitsMinutesByIntensityAndTotals() {
        // maxHR 200: 100 bpm = zone 1, 150 = zone 3, 180 = zone 5.
        let samples = [HRSamplePoint(t: 0, bpm: 100), HRSamplePoint(t: 120, bpm: 150),
                       HRSamplePoint(t: 240, bpm: 180), HRSamplePoint(t: 300, bpm: 180)]
        let summary = WatchCardioMinutesSummary.make(hrSamples: samples, maxHR: 200)
        XCTAssertEqual(summary?.belowModerateMinutes ?? -1, 2, accuracy: 0.01)
        XCTAssertEqual(summary?.moderateMinutes ?? -1, 2, accuracy: 0.01)
        XCTAssertEqual(summary?.vigorousMinutes ?? -1, 1, accuracy: 0.01)
        XCTAssertEqual(summary?.totalMinutes ?? -1, 5, accuracy: 0.01)
    }

    func testNilWithoutEnoughHeartRate() {
        XCTAssertNil(WatchCardioMinutesSummary.make(hrSamples: [], maxHR: 190))
        XCTAssertNil(WatchCardioMinutesSummary.make(hrSamples: [HRSamplePoint(t: 0, bpm: 120)], maxHR: 190))
    }
}
