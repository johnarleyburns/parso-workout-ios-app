import XCTest
@testable import CadenceFeatures
import CadenceCore

final class WatchStrengthCompletionAttributionTests: XCTestCase {
    let fixedID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    let fixedDate = Date(timeIntervalSince1970: 1_800_000_000)
    let profile = CardioIntensityProfile(restingHR: 60, maximumHR: 180, maximumHRSource: .userEntered)
    var samples: [HRSamplePoint] { stride(from: 0.0, through: 1_800, by: 15).map { HRSamplePoint(t: $0, bpm: 140) } }

    func make(_ s: [HRSamplePoint], sets: Int = 8) -> WatchStrengthCompletionAttribution {
        WatchStrengthCompletionAttribution.make(
            samples: s, duration: 1_800, profile: profile, ownerWorkingSetCount: sets,
            completionID: fixedID, completedAt: fixedDate, weekKey: { _ in "2026-11-09" })
    }

    func testMeasuredStrengthSummaryUsesThePhoneAccumulatorExactly() {
        let p = make(samples)
        let phone = CardioMinuteAccumulator.summarize(duration: 1_800, samples: samples, profile: profile)
        XCTAssertTrue(p.showsHeartRate)
        XCTAssertEqual(p.hrSamples, samples)
        XCTAssertEqual(p.cardioSummary, phone)
        XCTAssertEqual(p.overlay.sets, 8)
        XCTAssertGreaterThan(phone.moderateEquivalentMinutes, 0)
        XCTAssertEqual(p.overlay.moderateEquivalentMinutes, phone.moderateEquivalentMinutes, accuracy: 0.001)
    }

    func testNoSamplesShowsNoChartAndCreditsZeroCardioRatherThanDuration() {
        let p = make([], sets: 3)
        XCTAssertFalse(p.showsHeartRate)
        XCTAssertNil(p.cardioSummary)
        XCTAssertEqual(p.overlay.sets, 3)
        XCTAssertEqual(p.overlay.moderateEquivalentMinutes, 0)
    }

    func testContributionUsesStableCompletionIdentityAndCurrentCompletionWeek() {
        let p = make(samples)
        XCTAssertEqual(p.overlay.id, fixedID)
        XCTAssertEqual(p.overlay.kind, .strength)
        XCTAssertEqual(p.overlay.weekKey, "2026-11-09")
    }
}
