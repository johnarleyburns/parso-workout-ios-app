#if canImport(SwiftData)
import Foundation
import Testing
import SwiftData
@testable import CadenceCore

/// Issue #562: Watch cardio import must use the shared HRR-capable profile.
@MainActor
struct WatchCardioImportProfileTests {
    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    private func completion(id: UUID = UUID()) -> WatchCardioCompletion {
        let start = Date(timeIntervalSince1970: 50_000)
        var samples: [HRSamplePoint] = []
        for t in 0..<600 { samples.append(HRSamplePoint(t: Double(t), bpm: t < 300 ? 111 : 130)) }
        return WatchCardioCompletion(id: id, type: .run, start: start,
                                     end: start.addingTimeInterval(600), hrSamples: samples,
                                     avgHeartRate: 120, maxHeartRate: 130, gpsEnabled: false)
    }

    private func imported(_ c: WatchCardioCompletion, profile: CardioIntensityProfile,
                          in ctx: ModelContext) throws -> CardioMinuteSummary {
        #expect(try WorkoutRepository.ingest(c, profile: profile, in: ctx))
        return try #require(try WorkoutRepository.allCardio(ctx).first?.intensitySummary)
    }

    /// Mirrors `AppModel.currentIntensityProfile()` with a cached snapshot.
    private func shared(resting: Double?, override: Double? = nil, age: Int? = 50) -> CardioIntensityProfile {
        CardioIntensityProfile.resolved(restingHR: resting, userEnteredMaximumHR: override,
                                        age: age, updatedAt: Date())
    }

    @Test func cachedRestingHRUsesHRRAndMatchesPhoneProfile() throws {
        let profile = shared(resting: 63)
        #expect(profile.restingHR == 63)
        #expect(abs((profile.maximumHR ?? 0) - 173) <= 0.01)
        let c = completion()
        let summary = try imported(c, profile: profile, in: try makeContext())
        let expected = CardioMinuteAccumulator.summarize(
            duration: 600, samples: c.hrSamples,
            profile: CardioIntensityProfile(restingHR: 63, maximumHR: 173))
        #expect(abs(summary.moderateDuration - expected.moderateDuration) <= 2)
        #expect(abs(summary.vigorousDuration - expected.vigorousDuration) <= 2)
        #expect(summary.method == expected.method)
        #expect(summary.moderateDuration > 0)
        #expect(summary.vigorousDuration > 0)
    }

    @Test func noSnapshotFallsBackToPercentMaxWithoutInventingRestingHR() throws {
        let profile = shared(resting: nil)
        #expect(profile.restingHR == nil)
        let summary = try imported(completion(), profile: profile, in: try makeContext())
        let hrr = CardioMinuteAccumulator.summarize(
            duration: 600, samples: completion().hrSamples,
            profile: CardioIntensityProfile(restingHR: 63, maximumHR: 173))
        #expect(summary.method != hrr.method)
    }

    @Test func userMaxOverrideWinsAndKeepsRestingHR() {
        let profile = shared(resting: 63, override: 190)
        #expect(abs((profile.maximumHR ?? 0) - 190) <= 0.01)
        #expect(profile.restingHR == 63)
    }

    @Test func duplicateCompletionDoesNotRewriteIntensitySummary() throws {
        let ctx = try makeContext()
        let c = completion()
        let first = try imported(c, profile: shared(resting: 63), in: ctx)
        #expect(!(try WorkoutRepository.ingest(c, profile: shared(resting: nil), in: ctx)))
        let rows = try WorkoutRepository.allCardio(ctx)
        #expect(rows.count == 1)
        #expect(rows.first?.intensitySummary == first)
    }

    @Test func handlerUsesSharedCurrentIntensityProfile() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: repo.appendingPathComponent("Cadence/Cadence/App/AppModel.swift"),
                              encoding: .utf8)
        let start = try #require(text.range(of: "private func handleWatchCardioCompletion("))
        let rest = text[start.upperBound...]
        let end = try #require(rest.range(of: "private func completionAck"))
        let body = String(rest[..<end.lowerBound])
        #expect(body.contains("let profile = currentIntensityProfile()"))
        #expect(body.contains("ingest(completion, profile: profile, in: ctx)"))
        #expect(!body.contains("CardioIntensityProfile.resolved"))
        #expect(!body.contains("await"))
    }
}
#endif
