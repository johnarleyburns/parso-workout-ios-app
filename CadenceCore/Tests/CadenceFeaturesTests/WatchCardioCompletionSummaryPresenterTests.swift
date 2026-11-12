import XCTest
import CadenceCore
@testable import CadenceFeatures

final class WatchCardioCompletionSummaryPresenterTests: XCTestCase {
    private let profile = CardioIntensityProfile(restingHR: 63, maximumHR: 173, maximumHRSource: .userEntered)

    func testIntervalCompletionKeepsTheFinalizedSeriesForTheHeartRateChart() {
        let samples = [HRSamplePoint(t: 0, bpm: 115), HRSamplePoint(t: 60, bpm: 132),
                       HRSamplePoint(t: 120, bpm: 151)]
        let result = WatchCardioCompletionSummaryPresenter.present(
            samples: samples, duration: 180, averageBPM: 133, maximumBPM: 151, profile: profile)
        XCTAssertTrue(result.showsHeartRateChart)
        XCTAssertEqual(result.hrSamples, samples)
        XCTAssertEqual(result.averageBPM, 133)
        XCTAssertEqual(result.maximumBPM, 151)
    }

    func testIntervalMinuteAttributionExactlyMatchesSharedAccumulator() {
        let samples = stride(from: 0.0, through: 600, by: 30).map { HRSamplePoint(t: $0, bpm: 145) }
        let result = WatchCardioCompletionSummaryPresenter.present(
            samples: samples, duration: 600, averageBPM: 145, maximumBPM: 145, profile: profile)
        let expected = CardioMinuteAccumulator.summarize(duration: 600, samples: samples, profile: profile)
        XCTAssertEqual(result.minutes, WatchCardioMinutesSummary.make(summary: expected))
        XCTAssertNotNil(result.minutes)
    }

    func testNoMeasurementCompletionIsTruthfulAndDoesNotInventMinuteCredit() {
        let result = WatchCardioCompletionSummaryPresenter.present(
            samples: [], duration: 600, averageBPM: nil, maximumBPM: nil, profile: profile)
        XCTAssertFalse(result.showsHeartRateChart)
        XCTAssertNil(result.minutes)
    }

    func testRegularAndIntervalInputsProduceTheSamePresentation() {
        let samples = [HRSamplePoint(t: 0, bpm: 120), HRSamplePoint(t: 60, bpm: 150)]
        let a = WatchCardioCompletionSummaryPresenter.present(
            samples: samples, duration: 120, averageBPM: 135, maximumBPM: 150, profile: profile)
        let b = WatchCardioCompletionSummaryPresenter.present(
            samples: samples, duration: 120, averageBPM: 135, maximumBPM: 150, profile: profile)
        XCTAssertEqual(a, b)
    }
}

final class WatchCardioCompletionSummaryRouteTests: XCTestCase {
    func testIntervalAndSteadyCompletionUseTheSharedRichSummaryRoute() {
        XCTAssertEqual(WatchCardioCompletionRoute.forWorkout(.interval), .richSummary)
        XCTAssertEqual(WatchCardioCompletionRoute.forWorkout(.boxing), .richSummary)
        XCTAssertEqual(WatchCardioCompletionRoute.forWorkout(.steady), .richSummary)
    }
}
