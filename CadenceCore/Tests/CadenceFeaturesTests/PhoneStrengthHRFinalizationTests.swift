import XCTest
import SwiftData
import CadenceCore
import CadenceFeatures

private struct WindowSource: HealthHeartRateSource {
    var samples: [HealthHeartSample]
    func workouts(from: Date, to: Date) async throws -> [HealthWorkoutCandidate] { [] }
    func heartRate(for candidate: HealthWorkoutCandidate) async throws -> [(date: Date, bpm: Double)] { [] }
    func heartRateSamples(from: Date, to: Date) async throws -> [HealthHeartSample] { samples }
}

@MainActor
final class PhoneStrengthHRFinalizationTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 2_000_000)
    private let profile = CardioIntensityProfile(restingHR: 60, maximumHR: 190)

    private func makeSession() throws -> (ModelContext, WorkoutSession) {
        let ctx = ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
        let s = WorkoutSession(title: "Push", date: start, endedAt: start.addingTimeInterval(3_600))
        ctx.insert(s)
        try ctx.save()
        return (ctx, s)
    }

    private func obs(_ t: TimeInterval) -> HeartRateObservation {
        HeartRateObservation(source: .watchHealthKit, observedAt: start.addingTimeInterval(t), bpm: 150)
    }

    func testFinalizeIsIdempotent() throws {
        let (_, s) = try makeSession()
        let r = PhoneStrengthHeartRateRecorder(session: s)
        for i in 0..<60 { r.record(obs(Double(i) * 60), now: start.addingTimeInterval(3_600)) }
        XCTAssertTrue(r.finalize(profile: profile))
        let first = s.intensitySummary
        let stamp = s.hrCoverage?.recordedAt
        XCTAssertTrue(r.finalize(profile: profile, at: Date().addingTimeInterval(500)))
        XCTAssertEqual(s.intensitySummary, first)
        XCTAssertEqual(s.hrCoverage?.recordedAt, stamp)
        XCTAssertEqual(s.hrSamplePoints.count, 60)
    }

    func testManualOverrideSurvivesFinalize() throws {
        let (_, s) = try makeSession()
        s.setManualCardioMinutes(moderate: 7, vigorous: 3)
        let r = PhoneStrengthHeartRateRecorder(session: s)
        for i in 0..<60 { r.record(obs(Double(i) * 60), now: start.addingTimeInterval(3_600)) }
        XCTAssertTrue(r.finalize(profile: profile))
        XCTAssertTrue(s.hasManualCardioMinutesOverride)
        XCTAssertEqual(s.intensitySummary?.moderateDuration, 7 * 60)
        XCTAssertEqual(s.hrSamplePoints.count, 60)
    }

    func testPendingStateAndRetryOnActiveModel() throws {
        let (ctx, s) = try makeSession()
        s.endedAt = nil
        let active = ActiveWorkoutModel(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        active.startStrength(s)
        let recorder = try XCTUnwrap(active.heartRateRecorder)
        recorder.record(obs(60), now: start.addingTimeInterval(600))
        active.endStrength(now: start.addingTimeInterval(3_600))
        XCTAssertTrue(active.finalizeHeartRate(profile: profile, sessionID: s.id))
        XCTAssertNil(active.heartRatePendingSessionID)
        try ctx.save()
    }

    func testLegacyFallbackRequiresConfirmationAndStrictBounds() async throws {
        let (_, s) = try makeSession()
        let inside = stride(from: 5.0, to: 3_595, by: 5).map {
            HealthHeartSample(date: start.addingTimeInterval($0), bpm: 150, isAppleWatch: true)
        }
        let outside = [HealthHeartSample(date: start, bpm: 150, isAppleWatch: true),
                       HealthHeartSample(date: start.addingTimeInterval(4_000), bpm: 150, isAppleWatch: true),
                       HealthHeartSample(date: start.addingTimeInterval(30), bpm: 150, isAppleWatch: false)]
        let source = WindowSource(samples: inside + outside)
        let preview = await HeartRateRepair.run(session: s, source: source, profile: profile,
                                                confirmed: false, allowLegacyFallback: true)
        guard case .preview(let p) = preview else { return XCTFail("\(preview)") }
        XCTAssertTrue(p.isLegacyFallback)
        XCTAssertEqual(p.sampleCount, inside.count)
        XCTAssertTrue(s.hrSamplePoints.isEmpty, "preview must not modify")
        let applied = await HeartRateRepair.run(session: s, source: source, profile: profile,
                                                confirmed: true, allowLegacyFallback: true)
        guard case .repaired = applied else { return XCTFail("\(applied)") }
        XCTAssertEqual(s.hrSamplePoints.count, inside.count)
        XCTAssertTrue(HeartRateRepair.restorePrevious(s))
        XCTAssertTrue(s.hrSamplePoints.isEmpty)
    }

    func testLegacyFallbackRejectsNonWatchAndEmpty() async throws {
        let (_, s) = try makeSession()
        let phoneOnly = [HealthHeartSample(date: start.addingTimeInterval(30), bpm: 150, isAppleWatch: false)]
        let out = await HeartRateRepair.run(session: s, source: WindowSource(samples: phoneOnly), profile: profile,
                                            confirmed: false, allowLegacyFallback: true)
        XCTAssertEqual(out, .noMatch)
        let none = await HeartRateRepair.run(session: s, source: WindowSource(samples: []), profile: profile,
                                             confirmed: true, allowLegacyFallback: true)
        XCTAssertEqual(none, .noMatch)
        XCTAssertTrue(s.hrSamplePoints.isEmpty)
    }
}
