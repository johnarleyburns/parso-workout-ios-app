import Foundation
import Testing
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

struct WatchCardioTimingTests {
    /// Field bug: a strength workout was running on the phone (so the Watch held
    /// one `HKWorkoutSession` for heart-rate relay), then an 8-minute HIIT ran on
    /// the Watch. The cardio completion borrowed the shared strength session
    /// start, so its duration became the strength span plus the HIIT span.
    @Test func cardioCompletionDoesNotAbsorbTheSharedStrengthSession() {
        let strengthStart = Date(timeIntervalSince1970: 1_000_000)
        let hiitStart = strengthStart.addingTimeInterval(26 * 60)
        let hiitEnd = hiitStart.addingTimeInterval(8 * 60)

        // The buggy span (shared strength start) reports 34 minutes.
        let borrowed = hiitEnd.timeIntervalSince(strengthStart)
        #expect(abs(borrowed - 34 * 60) <= 0.5)

        // Fixed: the cardio session's own start wins.
        let timing = WatchCardioTiming(cardioSessionStart: hiitStart,
                                       measuredDuration: 8 * 60, endedAt: hiitEnd)
        #expect(timing.start == hiitStart)
        #expect(timing.end == hiitEnd)
        #expect(abs(timing.duration - 8 * 60) <= 0.5)
    }

    @Test func cardioCompletionFallsBackToMeasuredDuration() {
        let end = Date(timeIntervalSince1970: 2_000_000)
        let timing = WatchCardioTiming(cardioSessionStart: nil,
                                       measuredDuration: 480, endedAt: end)
        #expect(timing.start == end.addingTimeInterval(-480))
        #expect(abs(timing.duration - 480) <= 0.5)
    }

    @Test func cardioCompletionClampsNegativeMeasuredDuration() {
        let end = Date(timeIntervalSince1970: 3_000_000)
        let timing = WatchCardioTiming(cardioSessionStart: nil,
                                       measuredDuration: -5, endedAt: end)
        #expect(timing.duration == 0)
        #expect(timing.start == end)
    }
}
