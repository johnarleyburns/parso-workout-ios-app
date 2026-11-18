import XCTest
import SwiftData
@testable import CadenceCore

/// Issue #562: Watch cardio import must use the shared HRR-capable profile.
@MainActor
final class WatchCardioImportProfileTests: XCTestCase {
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
        XCTAssertTrue(try WorkoutRepository.ingest(c, profile: profile, in: ctx))
        return try XCTUnwrap(try WorkoutRepository.allCardio(ctx).first?.intensitySummary)
    }

    /// Mirrors `AppModel.currentIntensityProfile()` with a cached snapshot.
    private func shared(resting: Double?, override: Double? = nil, age: Int? = 50) -> CardioIntensityProfile {
        CardioIntensityProfile.resolved(restingHR: resting, userEnteredMaximumHR: override,
                                        age: age, updatedAt: Date())
    }

    func testCachedRestingHRUsesHRRAndMatchesPhoneProfile() throws {
        let profile = shared(resting: 63)
        XCTAssertEqual(profile.restingHR, 63)
        XCTAssertEqual(profile.maximumHR ?? 0, 173, accuracy: 0.01)
        let c = completion()
        let summary = try imported(c, profile: profile, in: try makeContext())
        let expected = CardioMinuteAccumulator.summarize(
            duration: 600, samples: c.hrSamples,
            profile: CardioIntensityProfile(restingHR: 63, maximumHR: 173))
        XCTAssertEqual(summary.moderateDuration, expected.moderateDuration, accuracy: 2)
        XCTAssertEqual(summary.vigorousDuration, expected.vigorousDuration, accuracy: 2)
        XCTAssertEqual(summary.method, expected.method)
        XCTAssertGreaterThan(summary.moderateDuration, 0)
        XCTAssertGreaterThan(summary.vigorousDuration, 0)
    }

    func testNoSnapshotFallsBackToPercentMaxWithoutInventingRestingHR() throws {
        let profile = shared(resting: nil)
        XCTAssertNil(profile.restingHR)
        let summary = try imported(completion(), profile: profile, in: try makeContext())
        let hrr = CardioMinuteAccumulator.summarize(
            duration: 600, samples: completion().hrSamples,
            profile: CardioIntensityProfile(restingHR: 63, maximumHR: 173))
        XCTAssertNotEqual(summary.method, hrr.method)
    }

    func testUserMaxOverrideWinsAndKeepsRestingHR() {
        let profile = shared(resting: 63, override: 190)
        XCTAssertEqual(profile.maximumHR ?? 0, 190, accuracy: 0.01)
        XCTAssertEqual(profile.restingHR, 63)
    }

    func testDuplicateCompletionDoesNotRewriteIntensitySummary() throws {
        let ctx = try makeContext()
        let c = completion()
        let first = try imported(c, profile: shared(resting: 63), in: ctx)
        XCTAssertFalse(try WorkoutRepository.ingest(c, profile: shared(resting: nil), in: ctx))
        let rows = try WorkoutRepository.allCardio(ctx)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.intensitySummary, first)
    }

    func testHandlerUsesSharedCurrentIntensityProfile() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: repo.appendingPathComponent("Cadence/Cadence/App/AppModel.swift"),
                              encoding: .utf8)
        let start = try XCTUnwrap(text.range(of: "private func handleWatchCardioCompletion("))
        let rest = text[start.upperBound...]
        let end = try XCTUnwrap(rest.range(of: "private func completionAck"))
        let body = String(rest[..<end.lowerBound])
        XCTAssertTrue(body.contains("let profile = currentIntensityProfile()"))
        XCTAssertTrue(body.contains("ingest(completion, profile: profile, in: ctx)"))
        XCTAssertFalse(body.contains("CardioIntensityProfile.resolved"))
        XCTAssertFalse(body.contains("await"))
    }
}
