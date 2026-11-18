import Foundation
import Testing
import CadenceCore
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

struct WatchCardioMinutesSummaryTests {
    private let hrrProfile = CardioIntensityProfile(restingHR: 63, maximumHR: 173, maximumHRSource: .userEntered)
    private let maxOnlyProfile = CardioIntensityProfile(restingHR: nil, maximumHR: 173, maximumHRSource: .userEntered)

    private func dense(_ bpm: Double, from: Double, count: Int) -> [HRSamplePoint] {
        (0..<count).map { HRSamplePoint(t: from + Double($0) * 60, bpm: bpm) }
    }

    private func assertMatchesAccumulator(_ samples: [HRSamplePoint], duration: TimeInterval,
                                          profile: CardioIntensityProfile,
                                          sourceLocation: SourceLocation = #_sourceLocation) {
        let expected = CardioMinuteAccumulator.summarize(duration: duration, samples: samples, profile: profile)
        let got = WatchCardioMinutesSummary.make(hrSamples: samples, sessionDuration: duration, profile: profile)
        #expect((got?.belowModerateMinutes ?? -1) == expected.belowModerateDuration / 60, sourceLocation: sourceLocation)
        #expect((got?.moderateMinutes ?? -1) == expected.moderateDuration / 60, sourceLocation: sourceLocation)
        #expect((got?.vigorousMinutes ?? -1) == expected.vigorousDuration / 60, sourceLocation: sourceLocation)
        #expect((got?.totalMinutes ?? -1) == expected.classifiedDuration / 60, sourceLocation: sourceLocation)
    }

    @Test func hRRProfileClassifiesModerateAndVigorousLikePhone() {
        let samples = dense(111, from: 0, count: 5) + dense(130, from: 300, count: 5)
        let summary = WatchCardioMinutesSummary.make(hrSamples: samples, sessionDuration: 600, profile: hrrProfile)
        #expect(abs((summary?.moderateMinutes ?? -1) - 5) <= 0.0001)
        #expect(abs((summary?.vigorousMinutes ?? -1) - 5) <= 0.0001)
        #expect(abs((summary?.belowModerateMinutes ?? -1) - 0) <= 0.0001)
        assertMatchesAccumulator(samples, duration: 600, profile: hrrProfile)
    }

    /// E (field testing): the Watch summary's "Cardio attr" row must show the
    /// same guideline-weighted figure (moderate + 2x vigorous) the phone's
    /// "Guideline credit" row already shows -- not the plain unweighted total.
    @Test func attributedMinutesMatchesModerateEquivalentFormula() {
        let samples = dense(111, from: 0, count: 5) + dense(130, from: 300, count: 5)
        let accumulated = CardioMinuteAccumulator.summarize(duration: 600, samples: samples, profile: hrrProfile)
        let summary = WatchCardioMinutesSummary.make(hrSamples: samples, sessionDuration: 600, profile: hrrProfile)
        #expect(abs((summary?.attributedMinutes ?? -1) - accumulated.moderateEquivalentMinutes) <= 0.0001)
        // Moderate + 2x vigorous must differ from the plain unweighted total
        // whenever there's any vigorous time, or this test can't tell the two
        // formulas apart.
        #expect(summary?.attributedMinutes != summary?.totalMinutes)
    }

    @Test func percentMaxFallbackWithoutRestingHRMatchesAccumulator() {
        let samples = dense(100, from: 0, count: 4) + dense(125, from: 240, count: 4) + dense(160, from: 480, count: 4)
        assertMatchesAccumulator(samples, duration: 720, profile: maxOnlyProfile)
    }

    @Test func longGapCarriesForwardTheLastKnownHeartRate() {
        let samples = [HRSamplePoint(t: 0, bpm: 130), HRSamplePoint(t: 600, bpm: 130)]
        let summary = WatchCardioMinutesSummary.make(hrSamples: samples, sessionDuration: 660, profile: hrrProfile)
        #expect(abs((summary?.vigorousMinutes ?? -1) - 11) <= 0.0001)
        #expect(abs((summary?.totalMinutes ?? -1) - 11) <= 0.0001)
        assertMatchesAccumulator(samples, duration: 660, profile: hrrProfile)
    }

    @Test func nilWithoutEnoughHeartRate() {
        #expect(WatchCardioMinutesSummary.make(hrSamples: [], sessionDuration: 0, profile: hrrProfile) == nil)
        #expect(WatchCardioMinutesSummary.make(hrSamples: [HRSamplePoint(t: 0, bpm: 120)],
                                                    sessionDuration: 60, profile: hrrProfile) == nil)
    }

    @Test func sourceDoesNotReferenceLegacyZoneMath() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/CadenceWorkoutFeatures/WatchCardioMinutesSummary.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        #expect(!source.contains("CardioZoneAggregator"))
        #expect(!source.contains("CardioMath"))
        #expect(source.contains("CardioMinuteAccumulator.summarize"))
    }
}
