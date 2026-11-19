#if canImport(SwiftData)
import Foundation
import Testing
import SwiftData
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures
import CadencePhoneFeatures

private struct WindowSource: HealthHeartRateSource {
    var samples: [HealthHeartSample]
    func workouts(from: Date, to: Date) async throws -> [HealthWorkoutCandidate] { [] }
    func heartRate(for candidate: HealthWorkoutCandidate) async throws -> [(date: Date, bpm: Double)] { [] }
    func heartRateSamples(from: Date, to: Date) async throws -> [HealthHeartSample] { samples }
}

@MainActor
struct PhoneStrengthHRFinalizationTests {
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

    @Test func finalizeIsIdempotent() throws {
        let (_, s) = try makeSession()
        let r = PhoneStrengthHeartRateRecorder(session: s)
        for i in 0..<60 { r.record(obs(Double(i) * 60), now: start.addingTimeInterval(3_600)) }
        #expect(r.finalize(profile: profile))
        let first = s.intensitySummary
        let stamp = s.hrCoverage?.recordedAt
        #expect(r.finalize(profile: profile, at: Date().addingTimeInterval(500)))
        #expect(s.intensitySummary == first)
        #expect(s.hrCoverage?.recordedAt == stamp)
        #expect(s.hrSamplePoints.count == 60)
    }

    @Test func manualOverrideSurvivesFinalize() throws {
        let (_, s) = try makeSession()
        s.setManualCardioMinutes(moderate: 7, vigorous: 3)
        let r = PhoneStrengthHeartRateRecorder(session: s)
        for i in 0..<60 { r.record(obs(Double(i) * 60), now: start.addingTimeInterval(3_600)) }
        #expect(r.finalize(profile: profile))
        #expect(s.hasManualCardioMinutesOverride)
        #expect(s.intensitySummary?.moderateDuration == TimeInterval(7 * 60))
        #expect(s.hrSamplePoints.count == 60)
    }

    @Test func pendingStateAndRetryOnActiveModel() throws {
        let (ctx, s) = try makeSession()
        s.endedAt = nil
        let active = ActiveWorkoutModel(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        active.startStrength(s)
        let recorder = try #require(active.heartRateRecorder)
        recorder.record(obs(60), now: start.addingTimeInterval(600))
        active.endStrength(now: start.addingTimeInterval(3_600))
        #expect(active.finalizeHeartRate(profile: profile, sessionID: s.id))
        #expect(active.heartRatePendingSessionID == nil)
        try ctx.save()
    }

    @Test func legacyFallbackRequiresConfirmationAndStrictBounds() async throws {
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
        guard case .preview(let p) = preview else {
            Issue.record("\(preview)")
            return
        }
        #expect(p.isLegacyFallback)
        #expect(p.sampleCount == inside.count)
        #expect(s.hrSamplePoints.isEmpty, "preview must not modify")
        let applied = await HeartRateRepair.run(session: s, source: source, profile: profile,
                                                confirmed: true, allowLegacyFallback: true)
        guard case .repaired = applied else {
            Issue.record("\(applied)")
            return
        }
        #expect(s.hrSamplePoints.count == inside.count)
        #expect(HeartRateRepair.restorePrevious(s))
        #expect(s.hrSamplePoints.isEmpty)
    }

    @Test func legacyFallbackRejectsNonWatchAndEmpty() async throws {
        let (_, s) = try makeSession()
        let phoneOnly = [HealthHeartSample(date: start.addingTimeInterval(30), bpm: 150, isAppleWatch: false)]
        let out = await HeartRateRepair.run(session: s, source: WindowSource(samples: phoneOnly), profile: profile,
                                            confirmed: false, allowLegacyFallback: true)
        #expect(out == .noMatch)
        let none = await HeartRateRepair.run(session: s, source: WindowSource(samples: []), profile: profile,
                                             confirmed: true, allowLegacyFallback: true)
        #expect(none == .noMatch)
        #expect(s.hrSamplePoints.isEmpty)
    }
}
#endif
