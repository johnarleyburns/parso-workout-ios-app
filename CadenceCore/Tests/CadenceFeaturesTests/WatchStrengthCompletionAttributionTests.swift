import Foundation
import Testing
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures
import CadenceCore

struct WatchStrengthCompletionAttributionTests {
    let fixedID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    let fixedDate = Date(timeIntervalSince1970: 1_800_000_000)
    let profile = CardioIntensityProfile(restingHR: 60, maximumHR: 180, maximumHRSource: .userEntered)
    var samples: [HRSamplePoint] { stride(from: 0.0, through: 1_800, by: 15).map { HRSamplePoint(t: $0, bpm: 140) } }

    func make(_ s: [HRSamplePoint], sets: Int = 8) -> WatchStrengthCompletionAttribution {
        WatchStrengthCompletionAttribution.make(
            samples: s, duration: 1_800, profile: profile, ownerWorkingSetCount: sets,
            completionID: fixedID, completedAt: fixedDate, weekKey: { _ in "2026-11-09" })
    }

    @Test func measuredStrengthSummaryUsesThePhoneAccumulatorExactly() {
        let p = make(samples)
        let phone = CardioMinuteAccumulator.summarize(duration: 1_800, samples: samples, profile: profile)
        #expect(p.showsHeartRate)
        #expect(p.hrSamples == samples)
        #expect(p.cardioSummary == phone)
        #expect(p.overlay.sets == 8)
        #expect(phone.moderateEquivalentMinutes > 0)
        #expect(abs(p.overlay.moderateEquivalentMinutes - phone.moderateEquivalentMinutes) <= 0.001)
    }

    @Test func noSamplesShowsNoChartAndCreditsZeroCardioRatherThanDuration() {
        let p = make([], sets: 3)
        #expect(!p.showsHeartRate)
        #expect(p.cardioSummary == nil)
        #expect(p.overlay.sets == 3)
        #expect(p.overlay.moderateEquivalentMinutes == 0)
    }

    @Test func contributionUsesStableCompletionIdentityAndCurrentCompletionWeek() {
        let p = make(samples)
        #expect(p.overlay.id == fixedID)
        #expect(p.overlay.kind == .strength)
        #expect(p.overlay.weekKey == "2026-11-09")
    }
}
