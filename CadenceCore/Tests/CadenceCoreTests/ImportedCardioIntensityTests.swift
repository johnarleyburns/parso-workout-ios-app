#if canImport(SwiftData)
import Foundation
import Testing
import SwiftData
@testable import CadenceCore

/// Issue #422: HealthKit-imported cardio must carry intensity provenance and credit.
@MainActor
struct ImportedCardioIntensityTests {
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

    @Test func insertStoresProfileAndSummaryWithCredit() throws {
        let c = try ctx()
        let report = try WorkoutRepository.ingest([workout()], intensityProfile: profile, in: c)
        #expect(report.inserted == 1)
        let row = try #require(try WorkoutRepository.allCardio(c).first)
        let s = try #require(row.intensitySummary)
        #expect(s.moderateDuration + s.vigorousDuration > 0)
        #expect(row.cardioAlgorithmVersion == s.algorithmVersion)
        #expect(row.intensityProfile == profile)
        #expect(row.trainingZonePolicy == CardioIntensityPolicy.trainingZonePolicy)
    }

    @Test func noHRFollowsAccumulatorFallback() throws {
        let c = try ctx()
        let w = workout(samples: [])
        _ = try WorkoutRepository.ingest([w], intensityProfile: profile, in: c)
        let row = try #require(try WorkoutRepository.allCardio(c).first)
        let expected = CardioMinuteAccumulator.summarize(duration: 600, samples: [], profile: profile)
        #expect(row.intensitySummary == expected)
    }

    @Test func replayBackfillsLegacyOnceWithoutDuplicate() throws {
        let c = try ctx()
        let w = workout()
        _ = try WorkoutRepository.ingest([w], in: c) // legacy: no intensity
        #expect(try WorkoutRepository.allCardio(c).first?.intensitySummary == nil)
        let first = try WorkoutRepository.ingest([w], intensityProfile: profile, in: c)
        #expect(first.enriched == 1)
        #expect(try WorkoutRepository.allCardio(c).count == 1)
        let stamp = try #require(try WorkoutRepository.allCardio(c).first).updatedAt
        let second = try WorkoutRepository.ingest([w], intensityProfile: profile, in: c)
        #expect(second.enriched == 0)
        #expect(second.unchanged == 1)
        #expect(!second.changedHistory)
        #expect(try WorkoutRepository.allCardio(c).first?.updatedAt == stamp)
    }

    @Test func backfillUpdatesImportedOnlyAndRerunIsNoOp() throws {
        let c = try ctx()
        _ = try WorkoutRepository.ingest([workout()], in: c)
        let recorded = CardioWorkout(type: .run, start: t0, end: t0.addingTimeInterval(600),
                                     source: .iphone)
        c.insert(recorded)
        try c.save()
        #expect(try WorkoutRepository.backfillImportedCardioIntensity(profile: profile, in: c) == 1)
        #expect(try WorkoutRepository.backfillImportedCardioIntensity(profile: profile, in: c) == 0)
        #expect(recorded.intensitySummary == nil)
        let imported = try WorkoutRepository.allCardio(c).first { $0.originValue == .healthKitImported }
        let s = try #require(imported?.intensitySummary)
        #expect(s.moderateDuration + s.vigorousDuration > 0)
    }

    @Test func applyCardioImportCarriesProfile() throws {
        let c = try ctx()
        let r = try WorkoutRepository.applyCardioImport(upserts: [workout()], deletedIDs: [],
                                                        intensityProfile: profile, in: c)
        #expect(r.inserted == 1)
        #expect(try WorkoutRepository.allCardio(c).first?.intensitySummary != nil)
    }
}
#endif
