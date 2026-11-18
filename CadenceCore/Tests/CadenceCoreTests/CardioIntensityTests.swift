import Foundation
import Testing
@testable import CadenceCore

struct CardioIntensityTests {
    private let profile = CardioIntensityProfile(
        restingHR: 60, maximumHR: 200, maximumHRSource: .fieldTest)

    @Test func tanakaIsAnExplicitEstimate() {
        #expect(abs(HeartRateMaximum.tanaka(age: 40) - 180) <= 0.001)
        #expect(CardioIntensityProfile.ageEstimated(age: 40).maximumHRSource == .agePredicted)
    }

    @Test func maximumHRSourcePrecedence() {
        let profile = CardioIntensityProfile.resolved(
            laboratoryMaximumHR: 190, fieldMaximumHR: 200,
            observedMaximumHR: 210, userEnteredMaximumHR: 220, age: 30)
        #expect(profile.maximumHR == 190)
        #expect(profile.maximumHRSource == .laboratoryMeasured)
        let fallback = CardioIntensityProfile.resolved(userEnteredMaximumHR: 220, age: 30)
        #expect(fallback.maximumHR == 220)
        #expect(fallback.maximumHRSource == .userEntered)
    }

    @Test func z2PercentMaximumHeartRateReceivesModerateGuidelineCredit() {
        let profile = CardioIntensityProfile(
            maximumHR: 200, maximumHRSource: .userEntered)

        let result = CardioIntensityClassifier.classify(heartRate: 130, profile: profile)

        #expect(result.trainingZone == .z2)
        #expect(result.guidelineIntensity == .moderate)
    }

    /// Percent-max-HR fallback (no resting HR): the "zone 1" training-zone
    /// boundary must match the belowModerate guideline boundary exactly
    /// (both 0.50×max), so a 50-60%-max-HR minute can never be labeled
    /// "moderate" in guideline text while still being counted as zone 1.
    @Test func percentMaximumFallbackZoneBoundaryMatchesGuidelineBoundary() {
        let profile = CardioIntensityProfile(maximumHR: 200, maximumHRSource: .userEntered)

        // 55% of max HR: above the 50% belowModerate cutoff, so guideline is
        // "moderate" — the training zone must agree and report z2, not z1.
        let result = CardioIntensityClassifier.classify(heartRate: 110, profile: profile)

        #expect(result.guidelineIntensity == .moderate)
        #expect(result.trainingZone == .z2, "zone must not disagree with the moderate guideline credit")
    }

    @Test func hRRBoundariesAndGuidelineCredit() {
        let cases: [(Double, RelativeIntensity, GuidelineIntensity, TrainingZone)] = [
            (101, .veryLight, .belowModerate, .z1),
            (107, .light, .moderate, .z2),
            (119, .moderate, .moderate, .z3),
            (150, .vigorous, .vigorous, .z4),
            (198, .nearMaximal, .vigorous, .z5)
        ]
        for (bpm, relative, guideline, zone) in cases {
            let result = CardioIntensityClassifier.classify(heartRate: bpm, profile: profile)
            #expect(result.relativeIntensity == relative, "\(bpm) BPM")
            #expect(result.guidelineIntensity == guideline, "\(bpm) BPM")
            #expect(result.trainingZone == zone, "\(bpm) BPM")
            #expect(result.method == .heartRateReserve)
        }
    }

    @Test func z2AndZ3HRRTimeBothEarnCardioMinutes() {
        // 8 min Z2 (107 bpm) + 4 min Z3 (119 bpm) must credit 12 minutes.
        let summary = CardioMinuteAccumulator.summarize(
            duration: 720,
            samples: [HRSamplePoint(t: 0, bpm: 107), HRSamplePoint(t: 480, bpm: 119)],
            profile: profile)
        #expect(abs(summary.moderateDuration - 720) <= 0.001)
        #expect(abs(summary.belowModerateDuration - 0) <= 0.001)
        #expect(abs(summary.moderateEquivalentMinutes - 12) <= 0.001)
    }

    @Test func noEasyFractionalCredit() {
        let summary = CardioMinuteAccumulator.summarize(
            duration: 600,
            samples: [HRSamplePoint(t: 0, bpm: 90), HRSamplePoint(t: 300, bpm: 150)],
            profile: profile)
        #expect(abs(summary.belowModerateDuration - 300) <= 0.001)
        #expect(abs(summary.vigorousDuration - 300) <= 0.001)
        #expect(abs(summary.moderateEquivalentMinutes - 10) <= 0.001)
    }

    @Test func longHRGapCarriesPreviousReadingForward() {
        let summary = CardioMinuteAccumulator.summarize(
            duration: 600,
            samples: [HRSamplePoint(t: 0, bpm: 150), HRSamplePoint(t: 301, bpm: 150)],
            profile: profile)
        #expect(abs(summary.classifiedDuration - 600) <= 0.001)
        #expect(abs(summary.unclassifiedDuration - 0) <= 0.001)
    }

    @Test func missingInputsRemainUnclassified() {
        let summary = CardioMinuteAccumulator.summarize(
            duration: 120, samples: [HRSamplePoint(t: 0, bpm: 150)],
            profile: CardioIntensityProfile())
        #expect(abs(summary.classifiedDuration - 0) <= 0.001)
        #expect(abs(summary.unclassifiedDuration - 120) <= 0.001)
        #expect(summary.confidence == .unavailable)
    }

    @Test func weeklyAggregatorRecomputesLegacySamplesWithCurrentProfile() {
        let workout = CardioWorkout(type: .run, start: Date(timeIntervalSince1970: 100),
                                    end: Date(timeIntervalSince1970: 700))
        workout.hrSamples = [HRSample(t: 0, bpm: 150, cardio: workout),
                             HRSample(t: 300, bpm: 150, cardio: workout)]
        let weekly = WeeklyCardioAggregator.summarize(
            [workout], since: Date(timeIntervalSince1970: 0), profile: profile)
        #expect(abs(weekly.actualMinutes - 10) <= 0.001)
        #expect(abs(weekly.vigorousMinutes - 10) <= 0.001)
        #expect(abs(weekly.moderateEquivalentMinutes - 20) <= 0.001)
    }

    @Test func weeklyAggregatorRecomputesStoredSummaryForZ2WithCurrentProfile() {
        let workout = CardioWorkout(type: .run, start: Date(timeIntervalSince1970: 100),
                                    end: Date(timeIntervalSince1970: 700))
        workout.hrSamples = [0, 120, 240, 360, 480].map {
            HRSample(t: TimeInterval($0), bpm: 130, cardio: workout)
        }
        // Simulate a row saved before the Z2 fallback was corrected.
        workout.intensitySummary = CardioMinuteSummary(
            actualDuration: 600, classifiedDuration: 600, unclassifiedDuration: 0,
            belowModerateDuration: 600, moderateDuration: 0, vigorousDuration: 0,
            zoneDurations: [.z2: 600], method: .percentMaximumHeartRate,
            confidence: .estimated)

        let weekly = WeeklyCardioAggregator.summarize(
            [workout], since: Date(timeIntervalSince1970: 0),
            profile: CardioIntensityProfile(maximumHR: 200, maximumHRSource: .userEntered))

        #expect(abs(weekly.moderateMinutes - 10) <= 0.001)
        #expect(abs(weekly.moderateEquivalentMinutes - 10) <= 0.001)
        #expect(abs(weekly.belowModerateMinutes - 0) <= 0.001)
    }

    /// HRR formula (resting HR known): threshold = resting + 0.30×(max−resting).
    @Test func belowModerateThresholdBPMUsesHRRFormulaWhenRestingHRKnown() {
        let profile = CardioIntensityProfile(restingHR: 60, maximumHR: 200, maximumHRSource: .fieldTest)
        #expect(abs((profile.belowModerateThresholdBPM ?? 0) - 102) <= 0.001)
    }

    /// %MaxHR fallback (no resting HR): threshold = 0.50×max, matching the
    /// corrected zone-1/guideline boundary above.
    @Test func belowModerateThresholdBPMUsesPercentMaxFallbackWhenNoRestingHR() {
        let profile = CardioIntensityProfile(maximumHR: 200, maximumHRSource: .userEntered)
        #expect(abs((profile.belowModerateThresholdBPM ?? 0) - 100) <= 0.001)
    }

    @Test func belowModerateThresholdBPMIsNilWithoutAnyMaximumHR() {
        #expect(CardioIntensityProfile().belowModerateThresholdBPM == nil)
    }

    @Test func mETDoseStaysSeparateFromGuidelineCredit() {
        let estimate = METEstimator.cardio(type: .rowing, duration: 600)
        #expect(abs((estimate.standardMET ?? 0) - 7) <= 0.001)
        #expect(abs((estimate.metMinutes ?? 0) - 70) <= 0.001)
        #expect(estimate.method != .unavailable)
    }
}

import Testing
@testable import CadenceCore

@Suite struct ManualCardioMinutesTests {
    @Test func manualMinutesReplaceSplit() {
        let s = CardioMinuteSummary.manual(moderate: 20, vigorous: 10, sessionDuration: 600)
        #expect(s.moderateDuration == 1200)
        #expect(s.vigorousDuration == 600)
        #expect(s.moderateEquivalentMinutes == 40)
        #expect(s.actualDuration >= 1800)
        #expect(s.zoneDurations.isEmpty)
    }
}
