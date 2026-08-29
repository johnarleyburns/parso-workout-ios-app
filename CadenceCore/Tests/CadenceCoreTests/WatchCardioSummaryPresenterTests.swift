import XCTest
@testable import CadenceCore

final class WatchCardioSummaryPresenterTests: XCTestCase {
    func testEmptyAndInvalidSamplesHideHeartRate() {
        let result = WatchCardioSummaryPresenter.present(hrSamples: [
            HRSamplePoint(t: 0, bpm: 0), HRSamplePoint(t: .nan, bpm: 120),
            HRSamplePoint(t: 1, bpm: .infinity)
        ])
        XCTAssertFalse(result.showsHeartRate)
        XCTAssertNil(result.averageBPM)
        XCTAssertNil(result.maximumBPM)
    }

    func testSingleSampleProducesAverageAndMaximum() {
        let result = WatchCardioSummaryPresenter.present(hrSamples: [HRSamplePoint(t: 4, bpm: 145)])
        XCTAssertEqual(result.hrSamples.count, 1)
        XCTAssertEqual(result.averageBPM, 145)
        XCTAssertEqual(result.maximumBPM, 145)
    }

    func testMultipleSamplesAreSortedAndSummarizedFromValidValues() {
        let result = WatchCardioSummaryPresenter.present(hrSamples: [
            HRSamplePoint(t: 3, bpm: 160), HRSamplePoint(t: 1, bpm: 120),
            HRSamplePoint(t: 2, bpm: -1), HRSamplePoint(t: 4, bpm: 140)
        ])
        XCTAssertEqual(result.hrSamples.map(\.t), [1, 3, 4])
        XCTAssertEqual(result.averageBPM ?? 0, 140, accuracy: 0.001)
        XCTAssertEqual(result.maximumBPM, 160)
    }

    func testDownsamplingPreservesEndpoints() {
        let samples = (0..<20).map { HRSamplePoint(t: Double($0), bpm: 120 + Double($0)) }
        let result = WatchCardioSummaryPresenter.present(hrSamples: samples, maxPoints: 5)
        XCTAssertEqual(result.hrSamples.count, 5)
        XCTAssertEqual(result.hrSamples.first?.t, 0)
        XCTAssertEqual(result.hrSamples.last?.t, 19)
    }
}
