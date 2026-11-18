import Foundation
import Testing
import CadenceCore
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

struct WatchHRUnclassifiedTests {
    private let profile = CardioIntensityProfile(restingHR: 63, maximumHR: 173, maximumHRSource: .userEntered)

    @Test func denseSamplesAreNearlyFullyClassifiedWithNoMissingMessage() {
        let duration: TimeInterval = 35 * 60
        let samples = (0..<420).map { HRSamplePoint(t: Double($0) * 5, bpm: 120) }
        let summary = WatchStrengthHRCoverage.summary(samples: samples, duration: duration, profile: profile)
        #expect(summary!.classifiedDuration > duration - 10)
        #expect(WatchStrengthHRCoverage.unclassifiedNote(summary: summary) == nil)
        let p = WatchStrengthHRCoverage.presentation(samples: samples, duration: duration, profile: profile, pending: false)
        #expect(p.kind == .complete)
    }

    @Test func fourSamplesAcrossAnHourCarryForwardToCoverTheWorkout() {
        let samples = [0, 900, 1800, 2700].map { HRSamplePoint(t: Double($0), bpm: 130) }
        let summary = WatchStrengthHRCoverage.summary(samples: samples, duration: 3600, profile: profile)!
        #expect(abs(summary.classifiedDuration - 3600) <= 0.001)
        #expect(abs(summary.unclassifiedDuration - 0) <= 0.001)
        #expect(WatchStrengthHRCoverage.unclassifiedNote(summary: summary) == nil)
        #expect(WatchStrengthHRCoverage.presentation(samples: samples, duration: 3600, profile: profile,
                                                            pending: false).kind == .complete)
    }

    @Test func noSamplesInventNothing() {
        #expect(WatchStrengthHRCoverage.summary(samples: [], duration: 3600, profile: profile) == nil)
        #expect(WatchStrengthHRCoverage.unclassifiedNote(summary: nil) == nil)
        #expect(WatchStrengthHRCoverage.presentation(samples: [], duration: 3600, profile: profile,
                                                            pending: false).kind == .noMeasurements)
    }

    @Test func watchAndPhoneShareTheAccumulatorResult() {
        let samples = [0, 900, 1800].map { HRSamplePoint(t: Double($0), bpm: 130) }
        let direct = CardioMinuteAccumulator.summarize(duration: 3600, samples: samples, profile: profile)
        #expect(WatchStrengthHRCoverage.summary(samples: samples, duration: 3600, profile: profile) == direct)
        let phone = HeartRateCoveragePresentation.make(
            state: HeartRateCoverageState.evaluate(summary: direct, sampleCount: samples.count),
            sampleCount: samples.count, pending: false)
        #expect(WatchStrengthHRCoverage.presentation(samples: samples, duration: 3600, profile: profile,
                                                            pending: false) == phone)
    }
}
