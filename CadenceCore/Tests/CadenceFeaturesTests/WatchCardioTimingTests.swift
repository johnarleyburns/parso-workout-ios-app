import XCTest
@testable import CadenceFeatures

final class WatchCardioTimingTests: XCTestCase {
    /// Field bug: a strength workout was running on the phone (so the Watch held
    /// one `HKWorkoutSession` for heart-rate relay), then an 8-minute HIIT ran on
    /// the Watch. The cardio completion borrowed the shared strength session
    /// start, so its duration became the strength span plus the HIIT span.
    func testCardioCompletionDoesNotAbsorbTheSharedStrengthSession() {
        let strengthStart = Date(timeIntervalSince1970: 1_000_000)
        let hiitStart = strengthStart.addingTimeInterval(26 * 60)
        let hiitEnd = hiitStart.addingTimeInterval(8 * 60)

        // The buggy span (shared strength start) reports 34 minutes.
        let borrowed = hiitEnd.timeIntervalSince(strengthStart)
        XCTAssertEqual(borrowed, 34 * 60, accuracy: 0.5)

        // Fixed: the cardio session's own start wins.
        let timing = WatchCardioTiming(cardioSessionStart: hiitStart,
                                       measuredDuration: 8 * 60, endedAt: hiitEnd)
        XCTAssertEqual(timing.start, hiitStart)
        XCTAssertEqual(timing.end, hiitEnd)
        XCTAssertEqual(timing.duration, 8 * 60, accuracy: 0.5)
    }

    func testCardioCompletionFallsBackToMeasuredDuration() {
        let end = Date(timeIntervalSince1970: 2_000_000)
        let timing = WatchCardioTiming(cardioSessionStart: nil,
                                       measuredDuration: 480, endedAt: end)
        XCTAssertEqual(timing.start, end.addingTimeInterval(-480))
        XCTAssertEqual(timing.duration, 480, accuracy: 0.5)
    }

    func testCardioCompletionClampsNegativeMeasuredDuration() {
        let end = Date(timeIntervalSince1970: 3_000_000)
        let timing = WatchCardioTiming(cardioSessionStart: nil,
                                       measuredDuration: -5, endedAt: end)
        XCTAssertEqual(timing.duration, 0)
        XCTAssertEqual(timing.start, end)
    }
}
