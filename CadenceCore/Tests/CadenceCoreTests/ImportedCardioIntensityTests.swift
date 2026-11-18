import XCTest
import SwiftData
@testable import CadenceCore

/// Issue #422: HealthKit-imported cardio must carry intensity provenance and credit.
@MainActor
final class ImportedCardioIntensityTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 50_000)

    private func ctx() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    private var profile: CardioIntensityProfile {
        CardioIntensityProfile.resolved(restingHR: 60, userEnteredMaximumHR: nil, age: 40, updatedAt: t0)
    }

    private func workout(id: UUID = UUID(), samples: [HRSamplePoint]? = nil) -> IngestedWorkout {
        let hr = samples ?? (0..<600).map { HRSamplePoint(t: Double($0), bpm: 150) }
        return IngestedWorkout(id: id, type: .run, start: t0, end: t0.addingTimeInterval(600),
                               hrSamples: hr, importedKind: .running)
    }

    func testInsertStoresProfileAndSummaryWithCredit() throws {
        let c = try ctx()
        let report = try WorkoutRepository.ingest([workout()], intensityProfile: profile, in: c)
        XCTAssertEqual(report.inserted, 1)
        let row = try XCTUnwrap(try WorkoutRepository.allCardio(c).first)
        let s = try XCTUnwrap(row.intensitySummary)
        XCTAssertGreaterThan(s.moderateDuration + s.vigorousDuration, 0)
        XCTAssertEqual(row.cardioAlgorithmVersion, s.algorithmVersion)
        XCTAssertEqual(row.intensityProfile, profile)
        XCTAssertEqual(row.trainingZonePolicy, CardioIntensityPolicy.trainingZonePolicy)
    }

    func testNoHRFollowsAccumulatorFallback() throws {
        let c = try ctx()
        let w = workout(samples: [])
        _ = try WorkoutRepository.ingest([w], intensityProfile: profile, in: c)
        let row = try XCTUnwrap(try WorkoutRepository.allCardio(c).first)
        let expected = CardioMinuteAccumulator.summarize(duration: 600, samples: [], profile: profile)
        XCTAssertEqual(row.intensitySummary, expected)
    }

    func testReplayBackfillsLegacyOnceWithoutDuplicate() throws {
        let c = try ctx()
        let w = workout()
        _ = try WorkoutRepository.ingest([w], in: c) // legacy: no intensity
        XCTAssertNil(try WorkoutRepository.allCardio(c).first?.intensitySummary)
        let first = try WorkoutRepository.ingest([w], intensityProfile: profile, in: c)
        XCTAssertEqual(first.enriched, 1)
        XCTAssertEqual(try WorkoutRepository.allCardio(c).count, 1)
        let stamp = try XCTUnwrap(try WorkoutRepository.allCardio(c).first).updatedAt
        let second = try WorkoutRepository.ingest([w], intensityProfile: profile, in: c)
        XCTAssertEqual(second.enriched, 0)
        XCTAssertEqual(second.unchanged, 1)
        XCTAssertFalse(second.changedHistory)
        XCTAssertEqual(try WorkoutRepository.allCardio(c).first?.updatedAt, stamp)
    }

    func testBackfillUpdatesImportedOnlyAndRerunIsNoOp() throws {
        let c = try ctx()
        _ = try WorkoutRepository.ingest([workout()], in: c)
        let recorded = CardioWorkout(type: .run, start: t0, end: t0.addingTimeInterval(600),
                                     source: .iphone)
        c.insert(recorded)
        try c.save()
        XCTAssertEqual(try WorkoutRepository.backfillImportedCardioIntensity(profile: profile, in: c), 1)
        XCTAssertEqual(try WorkoutRepository.backfillImportedCardioIntensity(profile: profile, in: c), 0)
        XCTAssertNil(recorded.intensitySummary)
        let imported = try WorkoutRepository.allCardio(c).first { $0.originValue == .healthKitImported }
        let s = try XCTUnwrap(imported?.intensitySummary)
        XCTAssertGreaterThan(s.moderateDuration + s.vigorousDuration, 0)
    }

    func testApplyCardioImportCarriesProfile() throws {
        let c = try ctx()
        let r = try WorkoutRepository.applyCardioImport(upserts: [workout()], deletedIDs: [],
                                                        intensityProfile: profile, in: c)
        XCTAssertEqual(r.inserted, 1)
        XCTAssertNotNil(try WorkoutRepository.allCardio(c).first?.intensitySummary)
    }
}
