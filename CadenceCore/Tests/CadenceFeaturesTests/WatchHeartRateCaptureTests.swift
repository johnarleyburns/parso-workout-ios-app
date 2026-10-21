import XCTest
import SwiftData
@testable import CadenceFeatures
import CadenceCore

final class WatchHeartRateCaptureTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 10_000)
    private let profile = CardioIntensityProfile.ageEstimated(age: 40)

    func testRepeatedPollsOfSameSampleEndPersistOnce() {
        var r = WatchHeartRateSampleRecorder()
        let end = start.addingTimeInterval(30)
        XCTAssertTrue(r.record(bpm: 120, sampleEnd: end, now: end, sessionStart: start))
        for i in 1...5 {
            XCTAssertFalse(r.record(bpm: 120, sampleEnd: end, now: end.addingTimeInterval(Double(i)), sessionStart: start))
        }
        XCTAssertEqual(r.samples.count, 1)
    }

    func testPolledFirstThenCallbackDoesNotDuplicate() {
        var r = WatchHeartRateSampleRecorder()
        let end = start.addingTimeInterval(60)
        XCTAssertTrue(r.record(bpm: 130, sampleEnd: end, now: end, sessionStart: start))
        XCTAssertFalse(r.record(bpm: 130, sampleEnd: end, now: end.addingTimeInterval(2), sessionStart: start))
        XCTAssertEqual(r.samples, [HRSamplePoint(t: 60, bpm: 130)])
    }

    func testSeventyFiveMinuteSparseCallbacksWithPollsHaveNoLargeGap() {
        var r = WatchHeartRateSampleRecorder()
        for i in 0..<(75 * 12) {   // a new HealthKit sample every 5 s
            let end = start.addingTimeInterval(Double(i) * 5)
            r.record(bpm: 125, sampleEnd: end, now: end, sessionStart: start)
            r.record(bpm: 125, sampleEnd: end, now: end.addingTimeInterval(1), sessionStart: start) // repeat poll
        }
        let duration = 75 * 60.0
        let out = r.finalSamples(duration: duration)
        XCTAssertEqual(HeartRateCoverage.measure(out, source: .watchHealthKit).largestGap, 5)
        let summary = CardioMinuteAccumulator.summarize(duration: duration, samples: out, profile: profile)
        XCTAssertLessThan(summary.unclassifiedDuration, 60)
    }

    func testScreenOffDoesNotClearRecorder() {
        var r = WatchHeartRateSampleRecorder()
        r.record(bpm: 110, sampleEnd: start.addingTimeInterval(5), now: start, sessionStart: start)
        // Display visibility is not an input; later samples simply append.
        r.record(bpm: 111, sampleEnd: start.addingTimeInterval(600), now: start, sessionStart: start)
        XCTAssertEqual(r.samples.count, 2)
    }

    func testBLECadenceAndBound() {
        var r = WatchHeartRateSampleRecorder(maxStored: 100)
        for i in 0..<3 { r.record(bpm: 120, sampleEnd: nil, now: start.addingTimeInterval(Double(i)), sessionStart: start) }
        XCTAssertEqual(r.samples.count, 1)
        XCTAssertTrue(r.record(bpm: 150, sampleEnd: nil, now: start.addingTimeInterval(3), sessionStart: start))
        for i in 0..<5_000 { r.record(bpm: Double(100 + i % 40), sampleEnd: nil, now: start.addingTimeInterval(10 + Double(i) * 6), sessionStart: start) }
        XCTAssertLessThanOrEqual(r.samples.count, 100)
    }

    func testDownsamplePreservesExtremaAndEnds() {
        let pts = (0..<5_000).map { HRSamplePoint(t: Double($0), bpm: $0 == 2_500 ? 200 : 100 + Double($0 % 7)) }
        let out = HRSampleNormalizer.normalize(pts, maxCount: 200)
        XCTAssertLessThanOrEqual(out.count, 200)
        XCTAssertEqual(out.first?.t, 0); XCTAssertEqual(out.last?.t, 4_999)
        XCTAssertEqual(out.map(\.bpm).max(), 200)
        XCTAssertEqual(out, HRSampleNormalizer.normalize(pts, maxCount: 200))
    }

    func testResetClears() {
        var r = WatchHeartRateSampleRecorder()
        r.record(bpm: 120, sampleEnd: start, now: start, sessionStart: start)
        r.reset()
        XCTAssertTrue(r.samples.isEmpty)
        XCTAssertTrue(r.record(bpm: 120, sampleEnd: start, now: start, sessionStart: start))
    }

    func testMalformedTransportRejected() {
        XCTAssertTrue(WatchStrengthHeartRate.decode([1.0, 100, 2.0]).isEmpty)
        XCTAssertTrue(WatchStrengthHeartRate.decode("x").isEmpty)
        XCTAssertTrue(WatchStrengthHeartRate.decode([Double](repeating: 100, count: WatchStrengthHeartRate.maximumTransportDoubles + 2)).isEmpty)
        let out = WatchStrengthHeartRate.decode([30.0, 120, .nan, 120, 20, .infinity, 40, 10, 5_000, 130, 10, 140], duration: 600)
        XCTAssertEqual(out, [HRSamplePoint(t: 10, bpm: 140), HRSamplePoint(t: 30, bpm: 120)])
    }

    func testSparseVersusDenseClassification() {
        let duration = 3_600.0
        let sparse = [0, 900, 1_800, 2_700].map { HRSamplePoint(t: Double($0), bpm: 130) }
        let s = CardioMinuteAccumulator.summarize(duration: duration, samples: sparse, profile: profile)
        XCTAssertGreaterThan(s.unclassifiedDuration, 3_000)
        XCTAssertEqual(HeartRateCoverageState.evaluate(summary: s, sampleCount: 4),
                       .incomplete(unclassifiedFraction: s.unclassifiedDuration / duration))
        let dense = stride(from: 0.0, to: duration, by: 5).map { HRSamplePoint(t: $0, bpm: 130) }
        let d = CardioMinuteAccumulator.summarize(duration: duration, samples: dense, profile: profile)
        XCTAssertEqual(d.unclassifiedDuration, 0, accuracy: 1)
        XCTAssertEqual(HeartRateCoverageState.evaluate(summary: d, sampleCount: dense.count), .complete)
    }
}

private struct FakeSource: HealthHeartRateSource {
    var list: Result<[HealthWorkoutCandidate], HealthRepairError> = .success([])
    var hr: Result<[(date: Date, bpm: Double)], HealthRepairError> = .success([])
    func workouts(from: Date, to: Date) async throws -> [HealthWorkoutCandidate] { try list.get() }
    func heartRate(for candidate: HealthWorkoutCandidate) async throws -> [(date: Date, bpm: Double)] { try hr.get() }
}

@MainActor
final class HeartRateRepairTests: XCTestCase {
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

    func testRepairSucceedsAndRestoreRestores() async throws {
        let s = try makeSession(samples: sparse)
        let before = (s.hrSamplePoints, s.intensitySummary, s.hrCoverage)
        let out = await HeartRateRepair.run(session: s, source: FakeSource(list: .success([candidate]), hr: .success(denseHR)), profile: profile)
        guard case .repaired = out else { return XCTFail("\(out)") }
        XCTAssertEqual(s.hrCoverage?.source, .repairedHealthKit)
        XCTAssertLessThan(s.intensitySummary!.unclassifiedDuration, 60)
        XCTAssertTrue(HeartRateRepair.restorePrevious(s))
        XCTAssertEqual(s.hrSamplePoints, before.0)
        XCTAssertEqual(s.intensitySummary, before.1)
        XCTAssertEqual(s.hrCoverage, before.2)
        XCTAssertNil(s.hrBackup)
    }

    func testFailuresPreserveData() async throws {
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
            XCTAssertEqual(out, expected)
            XCTAssertEqual(s.hrSamplePoints, before)
            XCTAssertNil(s.hrBackup)
        }
    }

    func testMultipleMatchesRequireSelection() async throws {
        let s = try makeSession(samples: sparse)
        let other = HealthWorkoutCandidate(token: "b", start: start.addingTimeInterval(60), end: start.addingTimeInterval(3_500),
                                           isStrength: true, sourceName: "Other", isFromThisApp: false)
        let mine = HealthWorkoutCandidate(token: "c", start: start, end: start.addingTimeInterval(3_600),
                                          isStrength: true, sourceName: "Other", isFromThisApp: false)
        let out = await HeartRateRepair.run(session: s, source: FakeSource(list: .success([other, mine]), hr: .success(denseHR)), profile: profile)
        guard case .needsSelection(let list) = out else { return XCTFail("\(out)") }
        XCTAssertEqual(list.count, 2)
        XCTAssertEqual(s.hrSamplePoints, sparse)
    }

    func testWorseResultNeedsConfirmation() async throws {
        let dense = stride(from: 0.0, to: 3_600, by: 10).map { HRSamplePoint(t: $0, bpm: 130) }
        let s = try makeSession(samples: dense)
        let poor: [(date: Date, bpm: Double)] = [(start, 130), (start.addingTimeInterval(100), 130)]
        let out = await HeartRateRepair.run(session: s, source: FakeSource(list: .success([candidate]), hr: .success(poor)), profile: profile)
        guard case .needsReplacementConfirmation = out else { return XCTFail("\(out)") }
        XCTAssertEqual(s.hrSamplePoints, dense)
        let confirmed = await HeartRateRepair.run(session: s, source: FakeSource(list: .success([candidate]), hr: .success(poor)),
                                                  profile: profile, confirmReplacement: true)
        guard case .repaired = confirmed else { return XCTFail("\(confirmed)") }
    }

    func testRepairNeverBridgesLongGapAndRejectsBadSamples() async throws {
        let s = try makeSession()
        let hr: [(date: Date, bpm: Double)] = [(start, 130), (start.addingTimeInterval(10), .nan),
                                               (start.addingTimeInterval(20), 900), (start.addingTimeInterval(1_800), 130),
                                               (start.addingTimeInterval(9_999), 130)]
        _ = await HeartRateRepair.run(session: s, source: FakeSource(list: .success([candidate]), hr: .success(hr)), profile: profile)
        XCTAssertEqual(s.hrSamplePoints.count, 2)
        XCTAssertGreaterThan(s.intensitySummary!.unclassifiedDuration, 3_000)
    }

    private struct SaveFailure: Error {}

    private func preview(_ s: WorkoutSession, hr: [(date: Date, bpm: Double)]) async throws -> HeartRateRepairPreview {
        let out = await HeartRateRepair.run(session: s, source: FakeSource(list: .success([candidate]), hr: .success(hr)),
                                            profile: profile, confirmed: false)
        guard case .preview(let p) = out else { throw XCTSkip("\(out)") }
        return p
    }

    func testStoredWorkoutUUIDWinsOverOtherCandidates() async throws {
        let s = try makeSession(samples: sparse)
        let id = UUID()
        s.healthKitWorkoutUUID = id
        let exact = HealthWorkoutCandidate(token: id.uuidString, start: start, end: start.addingTimeInterval(3_600),
                                           isStrength: true, sourceName: "Watch", isFromThisApp: false)
        let out = await HeartRateRepair.run(session: s, source: FakeSource(list: .success([candidate, exact]), hr: .success(denseHR)),
                                            profile: profile, confirmed: false)
        guard case .preview(let p) = out else { return XCTFail("\(out)") }
        XCTAssertEqual(p.proposal.associationToken, id.uuidString)
    }

    func testAmbiguousLegacyNeverAutoApplies() async throws {
        let s = try makeSession(samples: sparse)
        let a = HealthWorkoutCandidate(token: "x", start: start, end: start.addingTimeInterval(3_600),
                                       isStrength: true, sourceName: "A", isFromThisApp: false)
        let b = HealthWorkoutCandidate(token: "y", start: start, end: start.addingTimeInterval(3_500),
                                       isStrength: true, sourceName: "B", isFromThisApp: false)
        let out = await HeartRateRepair.run(session: s, source: FakeSource(list: .success([a, b]), hr: .success(denseHR)), profile: profile)
        guard case .needsSelection = out else { return XCTFail("\(out)") }
        XCTAssertEqual(s.hrSamplePoints, sparse)
    }

    func testConfirmAppliesPreviewedObservationsEvenIfHealthChanges() async throws {
        let s = try makeSession(samples: sparse)
        let p = try await preview(s, hr: denseHR)
        // Health now would return different data; confirm must not re-query.
        let out = HeartRateRepair.apply(p.proposal, to: s)
        guard case .repaired = out else { return XCTFail("\(out)") }
        XCTAssertEqual(s.hrSamplePoints, p.proposal.observations)
        XCTAssertEqual(s.intensitySummary, p.proposal.summary)
        XCTAssertEqual(s.hrCoverage?.source, .repairedHealthKit)
        XCTAssertNotNil(s.hrBackup)
    }

    func testSessionChangeAfterPreviewIsStaleAndDoubleApplyDoesNotDoubleCredit() async throws {
        let s = try makeSession(samples: sparse)
        let p = try await preview(s, hr: denseHR)
        s.updatedAt = s.updatedAt.addingTimeInterval(5)
        XCTAssertEqual(HeartRateRepair.apply(p.proposal, to: s), .staleProposal)
        XCTAssertEqual(s.hrSamplePoints, sparse)
        s.updatedAt = p.proposal.sessionRevision
        guard case .repaired = HeartRateRepair.apply(p.proposal, to: s) else { return XCTFail() }
        let credited = s.intensitySummary
        XCTAssertEqual(HeartRateRepair.apply(p.proposal, to: s), .staleProposal)
        XCTAssertEqual(s.intensitySummary, credited)
    }

    func testSaveFailureDuringApplyRestoresEverythingExactly() async throws {
        let s = try makeSession(samples: sparse)
        let p = try await preview(s, hr: denseHR)
        let before = (s.hrSamplesData, s.intensitySummaryData, s.hrCoverageData, s.hrBackupData, s.updatedAt)
        let out = HeartRateRepair.apply(p.proposal, to: s, save: { throw SaveFailure() })
        XCTAssertEqual(out, .accessError(.query))
        XCTAssertEqual(s.hrSamplesData, before.0)
        XCTAssertEqual(s.intensitySummaryData, before.1)
        XCTAssertEqual(s.hrCoverageData, before.2)
        XCTAssertEqual(s.hrBackupData, before.3)
        XCTAssertEqual(s.updatedAt, before.4)
    }

    func testSaveFailureDuringUndoKeepsRepairAndBackup() async throws {
        let s = try makeSession(samples: sparse)
        let p = try await preview(s, hr: denseHR)
        _ = HeartRateRepair.apply(p.proposal, to: s)
        let repaired = (s.hrSamplesData, s.intensitySummaryData, s.hrCoverageData, s.hrBackupData, s.updatedAt)
        XCTAssertFalse(HeartRateRepair.restorePrevious(s, save: { throw SaveFailure() }))
        XCTAssertEqual(s.hrSamplesData, repaired.0)
        XCTAssertEqual(s.intensitySummaryData, repaired.1)
        XCTAssertEqual(s.hrCoverageData, repaired.2)
        XCTAssertEqual(s.hrBackupData, repaired.3)
        XCTAssertEqual(s.updatedAt, repaired.4)
        XCTAssertTrue(HeartRateRepair.restorePrevious(s))
        XCTAssertEqual(s.hrSamplePoints, sparse)
    }
}
