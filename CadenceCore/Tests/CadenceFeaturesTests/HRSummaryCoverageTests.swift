import Foundation
import Testing
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures
import CadenceCore

struct HRSummaryCoverageTests {
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

    @Test func stateUsesTrueSampleCountNotSynthetic() {
        #expect(data(count: 0).hrCoverageState == .none)
        #expect(data(count: 1).hrCoverageState == .complete)
        let cov = HeartRateCoverage(source: .phone, sampleCount: 0, firstOffset: 0, lastOffset: 0, largestGap: 0, recordedAt: Date())
        #expect(data(count: 5, coverage: cov).hrCoverageState == .none)
    }

    @Test func sparseSamplesCarryForwardAndRemainDistinctFromZero() {
        let sparse = data(count: 4, unclassified: 600)
        #expect(sparse.hrCoverageState == .complete)
        #expect(sparse.hrCoveragePresentation?.kind == .complete)
        #expect(data(count: 0).hrCoveragePresentation?.kind == .noMeasurements)
        #expect(data(count: 200).hrCoveragePresentation?.kind == .complete)
        #expect(data(count: 3, pending: true).hrCoveragePresentation?.kind == .pending)
    }

    @Test func diagnosticsLineIsPrivacySafe() {
        let c = HeartRateCoverage(source: .repairedHealthKit, sampleCount: 9, firstOffset: 0, lastOffset: 90, largestGap: 130, recordedAt: Date())
        #expect(c.diagnosticsLine == "HR coverage: samples=9 largestGap=130s source=repairedHealthKit")
    }

    @Test func sessionWithoutCoverageMetadataStillBuilds() {
        let s = WorkoutSession(title: "Old", date: Date(), endedAt: Date().addingTimeInterval(600))
        let d = WorkoutSummaryData.from(session: s)
        #expect(d.hrCoverage == nil)
        #expect(d.hrCoverageState == .none)
    }
}

struct WatchStrengthHRCoverageTests {
    private let profile = CardioIntensityProfile.ageEstimated(age: 40)
    private func present(_ samples: [HRSamplePoint], pending: Bool = false) -> HeartRateCoveragePresentation {
        WatchStrengthHRCoverage.presentation(samples: samples, duration: 1_000, profile: profile, pending: pending)
    }

    @Test func watchSummaryStates() {
        let dense = stride(from: 0.0, to: 1_000, by: 5).map { HRSamplePoint(t: $0, bpm: 130) }
        let sparse = [0, 100, 200, 300].map { HRSamplePoint(t: Double($0), bpm: 130) }
        #expect(present([]).kind == .noMeasurements)
        #expect(present(sparse).kind == .complete)
        #expect(present(dense).kind == .complete)
        #expect(present(sparse, pending: true).kind == .pending)
        #expect(present([]).accessibilityLabel.contains("unknown"))
        #expect(present(sparse).accessibilityLabel.contains("complete"))
    }

    @Test func diagnosticsLineIsPrivacySafe() {
        let c = HeartRateCoverage(source: .phone, sampleCount: 9, firstOffset: 0, lastOffset: 10, largestGap: 130, recordedAt: Date())
        let line = c.diagnosticsLine
        #expect(!line.contains("bpm"))
        #expect(!line.contains("-"), "no UUIDs or dates")
    }
}
