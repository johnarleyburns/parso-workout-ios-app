#if canImport(SwiftData)
import Foundation
import Testing
import SwiftData
@testable import CadenceCore

struct HealthKitCardioEligibilityTests {
    @Test func exactCladironOwnership() {
        #expect(HealthKitCardioEligibility.isCladironAuthored(bundleIdentifier: "guru.parso.ios-workout-app"))
        #expect(HealthKitCardioEligibility.isCladironAuthored(bundleIdentifier: "guru.parso.ios-workout-app.watchkitapp"))
        for other in ["com.apple.health", "com.apple.Fitness", "com.strava.stravaride",
                      "com.example.watchface", "com.example.cladiron", "guru.parso.ios-workout-app.other"] {
            #expect(!HealthKitCardioEligibility.isCladironAuthored(bundleIdentifier: other), "\(other)")
        }
    }

    @Test func coreActivitiesMap() {
        let expected: [UInt: CardioType] = [37: .run, 52: .walk, 13: .cycle, 46: .swim,
                                            35: .rowing, 63: .hiit, 8: .boxing]
        for (raw, type) in expected {
            #expect(HealthKitCardioEligibility.evaluate(rawActivityType: raw).eligibility?.cardioType == type)
        }
    }

    @Test func otherCardioIsImportedWithRawType() {
        for raw: UInt in [11, 64, 73, 77] {
            let e = HealthKitCardioEligibility.evaluate(rawActivityType: raw).eligibility
            #expect(e?.cardioType == .other)
            #expect(e?.importedKind == .other)
            #expect(e?.rawActivityType == raw)
        }
    }

    @Test func strengthNonCardioAndUnknownExcluded() {
        for raw: UInt in [50, 20, 62, 57, 29, 66, 99_999] {
            #expect(HealthKitCardioEligibility.evaluate(rawActivityType: raw).eligibility == nil, "\(raw)")
        }
    }
}

@MainActor
struct HealthKitCardioIngestPolicyTests {
    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    private let t0 = Date(timeIntervalSince1970: 50_000)

    @Test func sameUUIDInsertsOnceAndLateDataEnrichesSameRow() throws {
        let ctx = try makeContext()
        let id = UUID()
        let bare = IngestedWorkout(id: id, type: .walk, start: t0, end: t0.addingTimeInterval(900),
                                   importedKind: .walking)
        #expect(try WorkoutRepository.ingest([bare], in: ctx) == 1)
        var rich = bare
        rich.distanceMeters = 1200
        rich.hrSamples = [HRSamplePoint(t: 0, bpm: 100)]
        rich.provenance = HealthKitWorkoutProvenance(sourceName: "Strava", sourceBundleIdentifier: "com.strava")
        #expect(try WorkoutRepository.ingest([rich, rich], in: ctx) == 0)
        let all = try WorkoutRepository.allCardio(ctx)
        #expect(all.count == 1)
        #expect(all[0].distance == 1200)
        #expect(all[0].orderedHRSamples.count == 1)
        #expect(all[0].healthKitProvenance?.sourceName == "Strava")
    }

    @Test func distinctThirdPartyUUIDsWithSameTimingBothSurvive() throws {
        let ctx = try makeContext()
        let a = IngestedWorkout(id: UUID(), type: .run, start: t0, end: t0.addingTimeInterval(600), importedKind: .running)
        let b = IngestedWorkout(id: UUID(), type: .run, start: t0, end: t0.addingTimeInterval(600), importedKind: .running)
        #expect(try WorkoutRepository.ingest([a, b], in: ctx) == 2)
        #expect(try WorkoutRepository.allCardio(ctx).count == 2)
    }

    @Test func watchReconciliationAttachesUUIDWithoutBecomingImport() throws {
        let ctx = try makeContext()
        let completion = WatchCardioCompletion(type: .run, start: t0, end: t0.addingTimeInterval(600))
        #expect(try WorkoutRepository.ingest(completion, in: ctx))
        var hk = IngestedWorkout(id: UUID(), type: .run, start: t0, end: t0.addingTimeInterval(600),
                                 importedKind: .running)
        hk.provenance = HealthKitWorkoutProvenance(sourceName: "X", sourceBundleIdentifier: "x")
        #expect(try WorkoutRepository.ingest([hk], in: ctx) == 0)
        let row = try #require(try WorkoutRepository.allCardio(ctx).first)
        #expect(row.healthKitWorkoutUUID == hk.id)
        #expect(row.originValue == .cladironRecorded)
        #expect(row.healthKitProvenance == nil)
        // A different third-party workout is not time-matched onto the reconciled row.
        let other = IngestedWorkout(id: UUID(), type: .run, start: t0, end: t0.addingTimeInterval(600), importedKind: .running)
        #expect(try WorkoutRepository.ingest([other], in: ctx) == 1)
    }

    @Test func zeroDurationAndSparseSourcesHandled() throws {
        let ctx = try makeContext()
        let zero = IngestedWorkout(id: UUID(), type: .run, start: t0, end: t0, importedKind: .running)
        #expect(try WorkoutRepository.ingest([zero], in: ctx) == 0)
        let sparse = IngestedWorkout(id: UUID(), type: .other, start: t0, end: t0.addingTimeInterval(300),
                                     importedKind: .other,
                                     provenance: HealthKitWorkoutProvenance(sourceName: "", sourceBundleIdentifier: ""))
        #expect(try WorkoutRepository.ingest([sparse], in: ctx) == 1)
    }
}
#endif
