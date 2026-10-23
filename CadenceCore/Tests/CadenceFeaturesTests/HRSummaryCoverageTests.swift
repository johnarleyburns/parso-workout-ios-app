import XCTest
@testable import CadenceFeatures
import CadenceCore

final class HRSummaryCoverageTests: XCTestCase {
    private let profile = CardioIntensityProfile.ageEstimated(age: 40)
    private func summary(unclassified: TimeInterval) -> CardioMinuteSummary {
        let pts = unclassified > 0
            ? [0, 100, 200, 300].map { HRSamplePoint(t: Double($0), bpm: 130) }
            : stride(from: 0.0, to: 1_000, by: 5).map { HRSamplePoint(t: $0, bpm: 130) }
        return CardioMinuteAccumulator.summarize(duration: 1_000, samples: pts, profile: profile)
    }

    private func data(count: Int, unclassified: TimeInterval = 0, pending: Bool = false,
                      coverage: HeartRateCoverage? = nil) -> WorkoutSummaryData {
        WorkoutSummaryData(kind: .strength, title: "S", date: Date(), durationSec: 1_000,
                           cardioIntensity: summary(unclassified: unclassified),
                           hrCoverage: coverage, hrSampleCount: count, hrCompletionPending: pending)
    }

    func testStateUsesTrueSampleCountNotSynthetic() {
        XCTAssertEqual(data(count: 0).hrCoverageState, .none)
        XCTAssertEqual(data(count: 1).hrCoverageState, .complete)
        let cov = HeartRateCoverage(source: .phone, sampleCount: 0, firstOffset: 0, lastOffset: 0, largestGap: 0, recordedAt: Date())
        XCTAssertEqual(data(count: 5, coverage: cov).hrCoverageState, .none)
    }

    func testSparseIsIncompleteAndDistinctFromZero() {
        let sparse = data(count: 4, unclassified: 600)
        guard case .incomplete = sparse.hrCoverageState else { return XCTFail() }
        XCTAssertEqual(sparse.hrCoveragePresentation?.kind, .incomplete)
        XCTAssertTrue(sparse.hrCoveragePresentation!.accessibilityLabel.contains("unclassified"))
        XCTAssertEqual(data(count: 0).hrCoveragePresentation?.kind, .noMeasurements)
        XCTAssertEqual(data(count: 200).hrCoveragePresentation?.kind, .complete)
        XCTAssertEqual(data(count: 3, pending: true).hrCoveragePresentation?.kind, .pending)
    }

    func testDiagnosticsLineIsPrivacySafe() {
        let c = HeartRateCoverage(source: .repairedHealthKit, sampleCount: 9, firstOffset: 0, lastOffset: 90, largestGap: 130, recordedAt: Date())
        XCTAssertEqual(c.diagnosticsLine, "HR coverage: samples=9 largestGap=130s source=repairedHealthKit")
    }

    func testSessionWithoutCoverageMetadataStillBuilds() {
        let s = WorkoutSession(title: "Old", date: Date(), endedAt: Date().addingTimeInterval(600))
        let d = WorkoutSummaryData.from(session: s)
        XCTAssertNil(d.hrCoverage)
        XCTAssertEqual(d.hrCoverageState, .none)
    }
}
