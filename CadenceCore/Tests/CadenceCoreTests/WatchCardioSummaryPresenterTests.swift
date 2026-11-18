import Testing
@testable import CadenceCore

struct WatchCardioSummaryPresenterTests {
    @Test func emptyAndInvalidSamplesHideHeartRate() {
        let result = WatchCardioSummaryPresenter.present(hrSamples: [
            HRSamplePoint(t: 0, bpm: 0), HRSamplePoint(t: .nan, bpm: 120),
            HRSamplePoint(t: 1, bpm: .infinity)
        ])
        #expect(!result.showsHeartRate)
        #expect(result.averageBPM == nil)
        #expect(result.maximumBPM == nil)
    }

    @Test func singleSampleProducesAverageAndMaximum() {
        let result = WatchCardioSummaryPresenter.present(hrSamples: [HRSamplePoint(t: 4, bpm: 145)])
        #expect(result.hrSamples.count == 1)
        #expect(result.averageBPM == 145)
        #expect(result.maximumBPM == 145)
    }

    @Test func multipleSamplesAreSortedAndSummarizedFromValidValues() {
        let result = WatchCardioSummaryPresenter.present(hrSamples: [
            HRSamplePoint(t: 3, bpm: 160), HRSamplePoint(t: 1, bpm: 120),
            HRSamplePoint(t: 2, bpm: -1), HRSamplePoint(t: 4, bpm: 140)
        ])
        #expect(result.hrSamples.map(\.t) == [1, 3, 4])
        #expect(abs((result.averageBPM ?? 0) - 140) <= 0.001)
        #expect(result.maximumBPM == 160)
    }

    @Test func downsamplingPreservesEndpoints() {
        let samples = (0..<20).map { HRSamplePoint(t: Double($0), bpm: 120 + Double($0)) }
        let result = WatchCardioSummaryPresenter.present(hrSamples: samples, maxPoints: 5)
        #expect(result.hrSamples.count == 5)
        #expect(result.hrSamples.first?.t == 0)
        #expect(result.hrSamples.last?.t == 19)
    }
}
