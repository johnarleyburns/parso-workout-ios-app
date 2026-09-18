import XCTest
@testable import CadenceCore

final class CardioIntensityTests: XCTestCase {
    private let profile = CardioIntensityProfile(
        restingHR: 60, maximumHR: 200, maximumHRSource: .fieldTest)

    func testTanakaIsAnExplicitEstimate() {
        XCTAssertEqual(HeartRateMaximum.tanaka(age: 40), 180, accuracy: 0.001)
        XCTAssertEqual(CardioIntensityProfile.ageEstimated(age: 40).maximumHRSource, .agePredicted)
    }

    func testMaximumHRSourcePrecedence() {
        let profile = CardioIntensityProfile.resolved(
            laboratoryMaximumHR: 190, fieldMaximumHR: 200,
            observedMaximumHR: 210, userEnteredMaximumHR: 220, age: 30)
        XCTAssertEqual(profile.maximumHR, 190)
        XCTAssertEqual(profile.maximumHRSource, .laboratoryMeasured)
        let fallback = CardioIntensityProfile.resolved(userEnteredMaximumHR: 220, age: 30)
        XCTAssertEqual(fallback.maximumHR, 220)
        XCTAssertEqual(fallback.maximumHRSource, .userEntered)
    }

    func testHRRBoundariesAndGuidelineCredit() {
        let cases: [(Double, RelativeIntensity, GuidelineIntensity, TrainingZone)] = [
            (101, .veryLight, .belowModerate, .z1),
            (107, .light, .belowModerate, .z2),
            (119, .moderate, .moderate, .z3),
            (150, .vigorous, .vigorous, .z4),
            (198, .nearMaximal, .vigorous, .z5)
        ]
        for (bpm, relative, guideline, zone) in cases {
            let result = CardioIntensityClassifier.classify(heartRate: bpm, profile: profile)
            XCTAssertEqual(result.relativeIntensity, relative, "\(bpm) BPM")
            XCTAssertEqual(result.guidelineIntensity, guideline, "\(bpm) BPM")
            XCTAssertEqual(result.trainingZone, zone, "\(bpm) BPM")
            XCTAssertEqual(result.method, .heartRateReserve)
        }
    }

    func testNoEasyFractionalCredit() {
        let summary = CardioMinuteAccumulator.summarize(
            duration: 600,
            samples: [HRSamplePoint(t: 0, bpm: 90), HRSamplePoint(t: 300, bpm: 150)],
            profile: profile)
        XCTAssertEqual(summary.belowModerateDuration, 120, accuracy: 0.001)
        XCTAssertEqual(summary.vigorousDuration, 120, accuracy: 0.001)
        XCTAssertEqual(summary.moderateEquivalentMinutes, 4, accuracy: 0.001)
    }

    func testLongHRGapIsUnclassifiedRatherThanInterpolated() {
        let summary = CardioMinuteAccumulator.summarize(
            duration: 600,
            samples: [HRSamplePoint(t: 0, bpm: 150), HRSamplePoint(t: 301, bpm: 150)],
            profile: profile)
        XCTAssertEqual(summary.classifiedDuration, 240, accuracy: 0.001)
        XCTAssertEqual(summary.unclassifiedDuration, 360, accuracy: 0.001)
    }

    func testMissingInputsRemainUnclassified() {
        let summary = CardioMinuteAccumulator.summarize(
            duration: 120, samples: [HRSamplePoint(t: 0, bpm: 150)],
            profile: CardioIntensityProfile())
        XCTAssertEqual(summary.classifiedDuration, 0, accuracy: 0.001)
        XCTAssertEqual(summary.unclassifiedDuration, 120, accuracy: 0.001)
        XCTAssertEqual(summary.confidence, .unavailable)
    }

    func testWeeklyAggregatorRecomputesLegacySamplesWithCurrentProfile() {
        let workout = CardioWorkout(type: .run, start: Date(timeIntervalSince1970: 100),
                                    end: Date(timeIntervalSince1970: 700))
        workout.hrSamples = [HRSample(t: 0, bpm: 150, cardio: workout),
                             HRSample(t: 300, bpm: 150, cardio: workout)]
        let weekly = WeeklyCardioAggregator.summarize(
            [workout], since: Date(timeIntervalSince1970: 0), profile: profile)
        XCTAssertEqual(weekly.actualMinutes, 10, accuracy: 0.001)
        XCTAssertEqual(weekly.vigorousMinutes, 4, accuracy: 0.001)
        XCTAssertEqual(weekly.moderateEquivalentMinutes, 8, accuracy: 0.001)
    }

    func testMETDoseStaysSeparateFromGuidelineCredit() {
        let estimate = METEstimator.cardio(type: .rowing, duration: 600)
        XCTAssertEqual(estimate.standardMET ?? 0, 7, accuracy: 0.001)
        XCTAssertEqual(estimate.metMinutes ?? 0, 70, accuracy: 0.001)
        XCTAssertNotEqual(estimate.method, .unavailable)
    }
}
