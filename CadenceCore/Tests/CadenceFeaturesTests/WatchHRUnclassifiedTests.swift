import XCTest
import CadenceCore
@testable import CadenceFeatures

final class WatchHRUnclassifiedTests: XCTestCase {
    private let profile = CardioIntensityProfile(restingHR: 63, maximumHR: 173, maximumHRSource: .userEntered)

    func testDenseSamplesAreNearlyFullyClassifiedWithNoMissingMessage() {
        let duration: TimeInterval = 35 * 60
        let samples = (0..<420).map { HRSamplePoint(t: Double($0) * 5, bpm: 120) }
        let summary = WatchStrengthHRCoverage.summary(samples: samples, duration: duration, profile: profile)
        XCTAssertGreaterThan(summary!.classifiedDuration, duration - 10)
        XCTAssertNil(WatchStrengthHRCoverage.unclassifiedNote(summary: summary))
        let p = WatchStrengthHRCoverage.presentation(samples: samples, duration: duration, profile: profile, pending: false)
        XCTAssertEqual(p.kind, .complete)
    }

    func testFourSamplesAcrossAnHourAreCappedAndReportUnclassified() {
        let samples = [0, 900, 1800, 2700].map { HRSamplePoint(t: Double($0), bpm: 130) }
        let summary = WatchStrengthHRCoverage.summary(samples: samples, duration: 3600, profile: profile)!
        XCTAssertEqual(summary.classifiedDuration, 4 * CardioMinuteAccumulator.maximumSampleGap, accuracy: 0.001)
        XCTAssertEqual(summary.unclassifiedDuration, 3600 - 480, accuracy: 0.001)
        XCTAssertEqual(WatchStrengthHRCoverage.unclassifiedNote(summary: summary),
                       "52 min unclassified — heart-rate measurements were missing.")
        XCTAssertEqual(WatchStrengthHRCoverage.presentation(samples: samples, duration: 3600, profile: profile,
                                                            pending: false).kind, .incomplete)
    }

    func testNoSamplesInventNothing() {
        XCTAssertNil(WatchStrengthHRCoverage.summary(samples: [], duration: 3600, profile: profile))
        XCTAssertNil(WatchStrengthHRCoverage.unclassifiedNote(summary: nil))
        XCTAssertEqual(WatchStrengthHRCoverage.presentation(samples: [], duration: 3600, profile: profile,
                                                            pending: false).kind, .noMeasurements)
    }

    func testWatchAndPhoneShareTheAccumulatorResult() {
        let samples = [0, 900, 1800].map { HRSamplePoint(t: Double($0), bpm: 130) }
        let direct = CardioMinuteAccumulator.summarize(duration: 3600, samples: samples, profile: profile)
        XCTAssertEqual(WatchStrengthHRCoverage.summary(samples: samples, duration: 3600, profile: profile), direct)
        let phone = HeartRateCoveragePresentation.make(
            state: HeartRateCoverageState.evaluate(summary: direct, sampleCount: samples.count),
            sampleCount: samples.count, pending: false)
        XCTAssertEqual(WatchStrengthHRCoverage.presentation(samples: samples, duration: 3600, profile: profile,
                                                            pending: false), phone)
    }
}
