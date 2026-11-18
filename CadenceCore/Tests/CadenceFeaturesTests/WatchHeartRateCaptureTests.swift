#if canImport(SwiftData)
import Foundation
import Testing
import SwiftData
import CadencePhoneFeatures
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures
import CadenceCore

struct WatchHeartRateCaptureTests {
    private let start = Date(timeIntervalSince1970: 10_000)
    private let profile = CardioIntensityProfile.ageEstimated(age: 40)

    @Test func repeatedPollsOfSameSampleEndPersistOnce() {
        var r = WatchHeartRateSampleRecorder()
        let end = start.addingTimeInterval(30)
        let first = r.record(bpm: 120, sampleEnd: end, now: end, sessionStart: start)
        #expect(first)
        for i in 1...5 {
            let repeated = r.record(bpm: 120, sampleEnd: end, now: end.addingTimeInterval(Double(i)), sessionStart: start)
            #expect(!repeated)
        }
        #expect(r.samples.count == 1)
    }

    @Test func polledFirstThenCallbackDoesNotDuplicate() {
        var r = WatchHeartRateSampleRecorder()
        let end = start.addingTimeInterval(60)
        let first = r.record(bpm: 130, sampleEnd: end, now: end, sessionStart: start)
        #expect(first)
        let duplicate = r.record(bpm: 130, sampleEnd: end, now: end.addingTimeInterval(2), sessionStart: start)
        #expect(!duplicate)
        #expect(r.samples == [HRSamplePoint(t: 60, bpm: 130)])
    }

    @Test func seventyFiveMinuteSparseCallbacksWithPollsHaveNoLargeGap() {
        var r = WatchHeartRateSampleRecorder()
        for i in 0..<(75 * 12) {   // a new HealthKit sample every 5 s
            let end = start.addingTimeInterval(Double(i) * 5)
            r.record(bpm: 125, sampleEnd: end, now: end, sessionStart: start)
            r.record(bpm: 125, sampleEnd: end, now: end.addingTimeInterval(1), sessionStart: start) // repeat poll
        }
        let duration = 75 * 60.0
        let out = r.finalSamples(duration: duration)
        #expect(HeartRateCoverage.measure(out, source: .watchHealthKit).largestGap == 5)
        let summary = CardioMinuteAccumulator.summarize(duration: duration, samples: out, profile: profile)
        #expect(summary.unclassifiedDuration < 60)
    }

    @Test func screenOffDoesNotClearRecorder() {
        var r = WatchHeartRateSampleRecorder()
        r.record(bpm: 110, sampleEnd: start.addingTimeInterval(5), now: start, sessionStart: start)
        // Display visibility is not an input; later samples simply append.
        r.record(bpm: 111, sampleEnd: start.addingTimeInterval(600), now: start, sessionStart: start)
        #expect(r.samples.count == 2)
    }

    @Test func bLECadenceAndBound() {
        var r = WatchHeartRateSampleRecorder(maxStored: 100)
        for i in 0..<3 { r.record(bpm: 120, sampleEnd: nil, now: start.addingTimeInterval(Double(i)), sessionStart: start) }
        #expect(r.samples.count == 1)
        let accepted = r.record(bpm: 150, sampleEnd: nil, now: start.addingTimeInterval(3), sessionStart: start)
        #expect(accepted)
        for i in 0..<5_000 { r.record(bpm: Double(100 + i % 40), sampleEnd: nil, now: start.addingTimeInterval(10 + Double(i) * 6), sessionStart: start) }
        #expect(r.samples.count <= 100)
    }

    @Test func downsamplePreservesExtremaAndEnds() {
        let pts = (0..<5_000).map { HRSamplePoint(t: Double($0), bpm: $0 == 2_500 ? 200 : 100 + Double($0 % 7)) }
        let out = HRSampleNormalizer.normalize(pts, maxCount: 200)
        #expect(out.count <= 200)
        #expect(out.first?.t == 0); #expect(out.last?.t == 4_999)
        #expect(out.map(\.bpm).max() == 200)
        #expect(out == HRSampleNormalizer.normalize(pts, maxCount: 200))
    }

    @Test func resetClears() {
        var r = WatchHeartRateSampleRecorder()
        r.record(bpm: 120, sampleEnd: start, now: start, sessionStart: start)
        r.reset()
        #expect(r.samples.isEmpty)
        let accepted = r.record(bpm: 120, sampleEnd: start, now: start, sessionStart: start)
        #expect(accepted)
    }

    @Test func malformedTransportRejected() {
        #expect(WatchStrengthHeartRate.decode([1.0, 100, 2.0]).isEmpty)
        #expect(WatchStrengthHeartRate.decode("x").isEmpty)
        #expect(WatchStrengthHeartRate.decode([Double](repeating: 100, count: WatchStrengthHeartRate.maximumTransportDoubles + 2)).isEmpty)
        let out = WatchStrengthHeartRate.decode([30.0, 120, .nan, 120, 20, .infinity, 40, 10, 5_000, 130, 10, 140], duration: 600)
        #expect(out == [HRSamplePoint(t: 10, bpm: 140), HRSamplePoint(t: 30, bpm: 120)])
    }

    @Test func sparseVersusDenseClassification() {
        let duration = 3_600.0
        let sparse = [0, 900, 1_800, 2_700].map { HRSamplePoint(t: Double($0), bpm: 130) }
        let s = CardioMinuteAccumulator.summarize(duration: duration, samples: sparse, profile: profile)
        #expect(abs(s.unclassifiedDuration - 0) <= 0.001)
        #expect(HeartRateCoverageState.evaluate(summary: s, sampleCount: 4) == .complete)
        let dense = stride(from: 0.0, to: duration, by: 5).map { HRSamplePoint(t: $0, bpm: 130) }
        let d = CardioMinuteAccumulator.summarize(duration: duration, samples: dense, profile: profile)
        #expect(abs(d.unclassifiedDuration - 0) <= 1)
        #expect(HeartRateCoverageState.evaluate(summary: d, sampleCount: dense.count) == .complete)
    }
}

private struct FakeSource: HealthHeartRateSource {
    var list: Result<[HealthWorkoutCandidate], HealthRepairError> = .success([])
    var hr: Result<[(date: Date, bpm: Double)], HealthRepairError> = .success([])
    func workouts(from: Date, to: Date) async throws -> [HealthWorkoutCandidate] { try list.get() }
    func heartRate(for candidate: HealthWorkoutCandidate) async throws -> [(date: Date, bpm: Double)] { try hr.get() }
}

@MainActor
final class HeartRateRepairTests {
    private struct UnexpectedOutcome: Error {}

    private let start = Date(timeIntervalSince1970: 50_000)
    private let profile = CardioIntensityProfile.ageEstimated(age: 40)
    private var container: ModelContainer!

    private func makeSession(samples: [HRSamplePoint] = []) throws -> WorkoutSession {
        container = try CadenceStore.makeModelContainer(inMemory: true)
        let s = WorkoutSession(title: "Strength", date: start, endedAt: start.addingTimeInterval(3_600))
        ModelContext(container).insert(s)
        s.recordHeartRate(samples, profile: profile, source: .watchHealthKit)
        return s
    }
    private var candidate: HealthWorkoutCandidate {
        HealthWorkoutCandidate(token: "a", start: start, end: start.addingTimeInterval(3_600),
                               isStrength: true, sourceName: "Watch", isFromThisApp: true)
    }
    private var denseHR: [(date: Date, bpm: Double)] {
        stride(from: 0.0, to: 3_600, by: 5).map { (start.addingTimeInterval($0), 135) }
    }
    private var sparse: [HRSamplePoint] { [0, 1_000, 2_000].map { HRSamplePoint(t: Double($0), bpm: 120) } }

    @Test func repairSucceedsAndRestoreRestores() async throws {
        let s = try makeSession(samples: sparse)
        let before = (s.hrSamplePoints, s.intensitySummary, s.hrCoverage)
        let out = await HeartRateRepair.run(session: s, source: FakeSource(list: .success([candidate]), hr: .success(denseHR)), profile: profile)
        guard case .repaired = out else {
            Issue.record("\(out)")
            return
        }
        #expect(s.hrCoverage?.source == .repairedHealthKit)
        #expect(s.intensitySummary!.unclassifiedDuration < 60)
        #expect(HeartRateRepair.restorePrevious(s))
        #expect(s.hrSamplePoints == before.0)
        #expect(s.intensitySummary == before.1)
        #expect(s.hrCoverage == before.2)
        #expect(s.hrBackup == nil)
    }

    @Test func failuresPreserveData() async throws {
        let s = try makeSession(samples: sparse)
        let before = s.hrSamplePoints
        let cases: [(FakeSource, HeartRateRepairOutcome)] = [
            (FakeSource(list: .success([])), .noMatch),
            (FakeSource(list: .success([candidate]), hr: .success([])), .noHeartRateSamples),
            (FakeSource(list: .failure(.authorization)), .accessError(.authorization)),
            (FakeSource(list: .success([candidate]), hr: .failure(.query)), .accessError(.query)),
        ]
        for (src, expected) in cases {
            let out = await HeartRateRepair.run(session: s, source: src, profile: profile)
            #expect(out == expected)
            #expect(s.hrSamplePoints == before)
            #expect(s.hrBackup == nil)
        }
    }

    @Test func multipleMatchesRequireSelection() async throws {
        let s = try makeSession(samples: sparse)
        let other = HealthWorkoutCandidate(token: "b", start: start.addingTimeInterval(60), end: start.addingTimeInterval(3_500),
                                           isStrength: true, sourceName: "Other", isFromThisApp: false)
        let mine = HealthWorkoutCandidate(token: "c", start: start, end: start.addingTimeInterval(3_600),
                                          isStrength: true, sourceName: "Other", isFromThisApp: false)
        let out = await HeartRateRepair.run(session: s, source: FakeSource(list: .success([other, mine]), hr: .success(denseHR)), profile: profile)
        guard case .needsSelection(let list) = out else {
            Issue.record("\(out)")
            return
        }
        #expect(list.count == 2)
        #expect(s.hrSamplePoints == sparse)
    }

    @Test func worseResultNeedsConfirmation() async throws {
        let dense = stride(from: 0.0, to: 3_600, by: 10).map { HRSamplePoint(t: $0, bpm: 130) }
        let s = try makeSession(samples: dense)
        let poor: [(date: Date, bpm: Double)] = [(start, 130), (start.addingTimeInterval(100), 130)]
        let out = await HeartRateRepair.run(session: s, source: FakeSource(list: .success([candidate]), hr: .success(poor)), profile: profile)
        guard case .needsReplacementConfirmation = out else {
            Issue.record("\(out)")
            return
        }
        #expect(s.hrSamplePoints == dense)
        let confirmed = await HeartRateRepair.run(session: s, source: FakeSource(list: .success([candidate]), hr: .success(poor)),
                                                  profile: profile, confirmReplacement: true)
        guard case .repaired = confirmed else {
            Issue.record("\(confirmed)")
            return
        }
    }

    @Test func repairCarriesForwardLongGapAndRejectsBadSamples() async throws {
        let s = try makeSession()
        let hr: [(date: Date, bpm: Double)] = [(start, 130), (start.addingTimeInterval(10), .nan),
                                               (start.addingTimeInterval(20), 900), (start.addingTimeInterval(1_800), 130),
                                               (start.addingTimeInterval(9_999), 130)]
        _ = await HeartRateRepair.run(session: s, source: FakeSource(list: .success([candidate]), hr: .success(hr)), profile: profile)
        #expect(s.hrSamplePoints.count == 2)
        #expect(abs(s.intensitySummary!.unclassifiedDuration - 0) <= 0.001)
    }

    private struct SaveFailure: Error {}

    private func preview(_ s: WorkoutSession, hr: [(date: Date, bpm: Double)]) async throws -> HeartRateRepairPreview {
        let out = await HeartRateRepair.run(session: s, source: FakeSource(list: .success([candidate]), hr: .success(hr)),
                                            profile: profile, confirmed: false)
        guard case .preview(let p) = out else {
            Issue.record("Expected .preview, got \(out)")
            throw UnexpectedOutcome()
        }
        return p
    }

    @Test func storedWorkoutUUIDWinsOverOtherCandidates() async throws {
        let s = try makeSession(samples: sparse)
        let id = UUID()
        s.healthKitWorkoutUUID = id
        let exact = HealthWorkoutCandidate(token: id.uuidString, start: start, end: start.addingTimeInterval(3_600),
                                           isStrength: true, sourceName: "Watch", isFromThisApp: false)
        let out = await HeartRateRepair.run(session: s, source: FakeSource(list: .success([candidate, exact]), hr: .success(denseHR)),
                                            profile: profile, confirmed: false)
        guard case .preview(let p) = out else {
            Issue.record("\(out)")
            return
        }
        #expect(p.proposal.associationToken == id.uuidString)
    }

    @Test func ambiguousLegacyNeverAutoApplies() async throws {
        let s = try makeSession(samples: sparse)
        let a = HealthWorkoutCandidate(token: "x", start: start, end: start.addingTimeInterval(3_600),
                                       isStrength: true, sourceName: "A", isFromThisApp: false)
        let b = HealthWorkoutCandidate(token: "y", start: start, end: start.addingTimeInterval(3_500),
                                       isStrength: true, sourceName: "B", isFromThisApp: false)
        let out = await HeartRateRepair.run(session: s, source: FakeSource(list: .success([a, b]), hr: .success(denseHR)), profile: profile)
        guard case .needsSelection = out else {
            Issue.record("\(out)")
            return
        }
        #expect(s.hrSamplePoints == sparse)
    }

    @Test func confirmAppliesPreviewedObservationsEvenIfHealthChanges() async throws {
        let s = try makeSession(samples: sparse)
        let p = try await preview(s, hr: denseHR)
        // Health now would return different data; confirm must not re-query.
        let out = HeartRateRepair.apply(p.proposal, to: s)
        guard case .repaired = out else {
            Issue.record("\(out)")
            return
        }
        #expect(s.hrSamplePoints == p.proposal.observations)
        #expect(s.intensitySummary == p.proposal.summary)
        #expect(s.hrCoverage?.source == .repairedHealthKit)
        #expect(s.hrBackup != nil)
    }

    @Test func sessionChangeAfterPreviewIsStaleAndDoubleApplyDoesNotDoubleCredit() async throws {
        let s = try makeSession(samples: sparse)
        let p = try await preview(s, hr: denseHR)
        s.updatedAt = s.updatedAt.addingTimeInterval(5)
        #expect(HeartRateRepair.apply(p.proposal, to: s) == .staleProposal)
        #expect(s.hrSamplePoints == sparse)
        s.updatedAt = p.proposal.sessionRevision
        guard case .repaired = HeartRateRepair.apply(p.proposal, to: s) else {
            Issue.record()
            return
        }
        let credited = s.intensitySummary
        #expect(HeartRateRepair.apply(p.proposal, to: s) == .staleProposal)
        #expect(s.intensitySummary == credited)
    }

    @Test func saveFailureDuringApplyRestoresEverythingExactly() async throws {
        let s = try makeSession(samples: sparse)
        let p = try await preview(s, hr: denseHR)
        let before = (s.hrSamplesData, s.intensitySummaryData, s.hrCoverageData, s.hrBackupData, s.updatedAt)
        let out = HeartRateRepair.apply(p.proposal, to: s, save: { throw SaveFailure() })
        #expect(out == .accessError(.query))
        #expect(s.hrSamplesData == before.0)
        #expect(s.intensitySummaryData == before.1)
        #expect(s.hrCoverageData == before.2)
        #expect(s.hrBackupData == before.3)
        #expect(s.updatedAt == before.4)
    }

    @Test func saveFailureDuringUndoKeepsRepairAndBackup() async throws {
        let s = try makeSession(samples: sparse)
        let p = try await preview(s, hr: denseHR)
        _ = HeartRateRepair.apply(p.proposal, to: s)
        let repaired = (s.hrSamplesData, s.intensitySummaryData, s.hrCoverageData, s.hrBackupData, s.updatedAt)
        #expect(!HeartRateRepair.restorePrevious(s, save: { throw SaveFailure() }))
        #expect(s.hrSamplesData == repaired.0)
        #expect(s.intensitySummaryData == repaired.1)
        #expect(s.hrCoverageData == repaired.2)
        #expect(s.hrBackupData == repaired.3)
        #expect(s.updatedAt == repaired.4)
        #expect(HeartRateRepair.restorePrevious(s))
        #expect(s.hrSamplePoints == sparse)
    }
}
#endif
