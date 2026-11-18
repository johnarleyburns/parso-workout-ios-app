import XCTest
import SwiftData
@testable import CadenceCore

final class HealthKitCardioEligibilityTests: XCTestCase {
    func testExactCladironOwnership() {
        XCTAssertTrue(HealthKitCardioEligibility.isCladironAuthored(bundleIdentifier: "guru.parso.ios-workout-app"))
        XCTAssertTrue(HealthKitCardioEligibility.isCladironAuthored(bundleIdentifier: "guru.parso.ios-workout-app.watchkitapp"))
        for other in ["com.apple.health", "com.apple.Fitness", "com.strava.stravaride",
                      "com.example.watchface", "com.example.cladiron", "guru.parso.ios-workout-app.other"] {
            XCTAssertFalse(HealthKitCardioEligibility.isCladironAuthored(bundleIdentifier: other), other)
        }
    }

    func testCoreActivitiesMap() {
        let expected: [UInt: CardioType] = [37: .run, 52: .walk, 13: .cycle, 46: .swim,
                                            35: .rowing, 63: .hiit, 8: .boxing]
        for (raw, type) in expected {
            XCTAssertEqual(HealthKitCardioEligibility.evaluate(rawActivityType: raw).eligibility?.cardioType, type)
        }
    }

    func testOtherCardioIsImportedWithRawType() {
        for raw: UInt in [11, 64, 73, 77] {
            let e = HealthKitCardioEligibility.evaluate(rawActivityType: raw).eligibility
            XCTAssertEqual(e?.cardioType, .other)
            XCTAssertEqual(e?.importedKind, .other)
            XCTAssertEqual(e?.rawActivityType, raw)
        }
    }

    func testStrengthNonCardioAndUnknownExcluded() {
        for raw: UInt in [50, 20, 62, 57, 29, 66, 99_999] {
            XCTAssertNil(HealthKitCardioEligibility.evaluate(rawActivityType: raw).eligibility, "\(raw)")
        }
    }
}

@MainActor
final class HealthKitCardioIngestPolicyTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    private let t0 = Date(timeIntervalSince1970: 50_000)

    func testSameUUIDInsertsOnceAndLateDataEnrichesSameRow() throws {
        let ctx = try makeContext()
        let id = UUID()
        let bare = IngestedWorkout(id: id, type: .walk, start: t0, end: t0.addingTimeInterval(900),
                                   importedKind: .walking)
        XCTAssertEqual(try WorkoutRepository.ingest([bare], in: ctx), 1)
        var rich = bare
        rich.distanceMeters = 1200
        rich.hrSamples = [HRSamplePoint(t: 0, bpm: 100)]
        rich.provenance = HealthKitWorkoutProvenance(sourceName: "Strava", sourceBundleIdentifier: "com.strava")
        XCTAssertEqual(try WorkoutRepository.ingest([rich, rich], in: ctx), 0)
        let all = try WorkoutRepository.allCardio(ctx)
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].distance, 1200)
        XCTAssertEqual(all[0].orderedHRSamples.count, 1)
        XCTAssertEqual(all[0].healthKitProvenance?.sourceName, "Strava")
    }

    func testDistinctThirdPartyUUIDsWithSameTimingBothSurvive() throws {
        let ctx = try makeContext()
        let a = IngestedWorkout(id: UUID(), type: .run, start: t0, end: t0.addingTimeInterval(600), importedKind: .running)
        let b = IngestedWorkout(id: UUID(), type: .run, start: t0, end: t0.addingTimeInterval(600), importedKind: .running)
        XCTAssertEqual(try WorkoutRepository.ingest([a, b], in: ctx), 2)
        XCTAssertEqual(try WorkoutRepository.allCardio(ctx).count, 2)
    }

    func testWatchReconciliationAttachesUUIDWithoutBecomingImport() throws {
        let ctx = try makeContext()
        let completion = WatchCardioCompletion(type: .run, start: t0, end: t0.addingTimeInterval(600))
        XCTAssertTrue(try WorkoutRepository.ingest(completion, in: ctx))
        var hk = IngestedWorkout(id: UUID(), type: .run, start: t0, end: t0.addingTimeInterval(600),
                                 importedKind: .running)
        hk.provenance = HealthKitWorkoutProvenance(sourceName: "X", sourceBundleIdentifier: "x")
        XCTAssertEqual(try WorkoutRepository.ingest([hk], in: ctx), 0)
        let row = try XCTUnwrap(try WorkoutRepository.allCardio(ctx).first)
        XCTAssertEqual(row.healthKitWorkoutUUID, hk.id)
        XCTAssertEqual(row.originValue, .cladironRecorded)
        XCTAssertNil(row.healthKitProvenance)
        // A different third-party workout is not time-matched onto the reconciled row.
        let other = IngestedWorkout(id: UUID(), type: .run, start: t0, end: t0.addingTimeInterval(600), importedKind: .running)
        XCTAssertEqual(try WorkoutRepository.ingest([other], in: ctx), 1)
    }

    func testZeroDurationAndSparseSourcesHandled() throws {
        let ctx = try makeContext()
        let zero = IngestedWorkout(id: UUID(), type: .run, start: t0, end: t0, importedKind: .running)
        XCTAssertEqual(try WorkoutRepository.ingest([zero], in: ctx), 0)
        let sparse = IngestedWorkout(id: UUID(), type: .other, start: t0, end: t0.addingTimeInterval(300),
                                     importedKind: .other,
                                     provenance: HealthKitWorkoutProvenance(sourceName: "", sourceBundleIdentifier: ""))
        XCTAssertEqual(try WorkoutRepository.ingest([sparse], in: ctx), 1)
    }
}
