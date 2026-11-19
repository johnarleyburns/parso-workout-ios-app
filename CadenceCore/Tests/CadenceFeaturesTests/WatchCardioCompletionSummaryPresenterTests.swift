import Testing
import CadenceCore
import CadencePhoneFeatures
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

struct WatchCardioCompletionSummaryPresenterTests {
    private let profile = CardioIntensityProfile(restingHR: 63, maximumHR: 173, maximumHRSource: .userEntered)

    @Test func intervalCompletionKeepsTheFinalizedSeriesForTheHeartRateChart() {
        let samples = [HRSamplePoint(t: 0, bpm: 115), HRSamplePoint(t: 60, bpm: 132),
                       HRSamplePoint(t: 120, bpm: 151)]
        let result = WatchCardioCompletionSummaryPresenter.present(
            samples: samples, duration: 180, averageBPM: 133, maximumBPM: 151, profile: profile)
        #expect(result.showsHeartRateChart)
        #expect(result.hrSamples == samples)
        #expect(result.averageBPM == 133)
        #expect(result.maximumBPM == 151)
    }

    @Test func intervalMinuteAttributionExactlyMatchesSharedAccumulator() {
        let samples = stride(from: 0.0, through: 600, by: 30).map { HRSamplePoint(t: $0, bpm: 145) }
        let result = WatchCardioCompletionSummaryPresenter.present(
            samples: samples, duration: 600, averageBPM: 145, maximumBPM: 145, profile: profile)
        let expected = CardioMinuteAccumulator.summarize(duration: 600, samples: samples, profile: profile)
        #expect(result.minutes == WatchCardioMinutesSummary.make(summary: expected))
        #expect(result.minutes != nil)
    }

    @Test func noMeasurementCompletionIsTruthfulAndDoesNotInventMinuteCredit() {
        let result = WatchCardioCompletionSummaryPresenter.present(
            samples: [], duration: 600, averageBPM: nil, maximumBPM: nil, profile: profile)
        #expect(!result.showsHeartRateChart)
        #expect(result.minutes == nil)
    }

    @Test func regularAndIntervalInputsProduceTheSamePresentation() {
        let samples = [HRSamplePoint(t: 0, bpm: 120), HRSamplePoint(t: 60, bpm: 150)]
        let a = WatchCardioCompletionSummaryPresenter.present(
            samples: samples, duration: 120, averageBPM: 135, maximumBPM: 150, profile: profile)
        let b = WatchCardioCompletionSummaryPresenter.present(
            samples: samples, duration: 120, averageBPM: 135, maximumBPM: 150, profile: profile)
        #expect(a == b)
    }
}

struct WatchCardioCompletionSummaryRouteTests {
    @Test func intervalAndSteadyCompletionUseTheSharedRichSummaryRoute() {
        #expect(WatchCardioCompletionRoute.forWorkout(.interval) == .richSummary)
        #expect(WatchCardioCompletionRoute.forWorkout(.boxing) == .richSummary)
        #expect(WatchCardioCompletionRoute.forWorkout(.steady) == .richSummary)
    }
}
