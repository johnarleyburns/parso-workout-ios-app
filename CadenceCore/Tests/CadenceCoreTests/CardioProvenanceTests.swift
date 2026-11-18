import XCTest
import SwiftData
@testable import CadenceCore

final class CardioProvenanceTests: XCTestCase {
    private func makeStore() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    private let full = HealthKitWorkoutProvenance(
        sourceName: "Strava", sourceBundleIdentifier: "com.strava", sourceVersion: "1",
        productType: "Watch7,1", deviceName: "Apple Watch", deviceManufacturer: "Apple Inc.",
        deviceModel: "Watch", deviceHardwareVersion: "Watch7,1", deviceSoftwareVersion: "11.0",
        workoutBrandName: "Peloton", isAppleFitnessPlus: true)

    func testProvenanceRoundTripsFullAndEmpty() {
        XCTAssertEqual(HealthKitWorkoutProvenance.decode(full.encodedString()), full)
        let empty = HealthKitWorkoutProvenance(sourceName: "", sourceBundleIdentifier: "")
        XCTAssertEqual(HealthKitWorkoutProvenance.decode(empty.encodedString()), empty)
        XCTAssertNil(HealthKitWorkoutProvenance.decode(""))
        XCTAssertNil(HealthKitWorkoutProvenance.decode("{\"version\":99,\"provenance\":{}}"))
    }

    func testLegacyAndUnknownOrigins() {
        let legacy = CardioWorkout()
        XCTAssertEqual(legacy.originValue, .cladironRecorded)
        XCTAssertNil(legacy.recordOriginRaw, "reading must not mutate")
        let kind = CardioWorkout(importedWorkoutKind: .running)
        XCTAssertEqual(kind.originValue, .healthKitImported)
        let future = CardioWorkout()
        future.recordOriginRaw = "someFutureOrigin"
        XCTAssertEqual(future.originValue, .unrecognized)
        XCTAssertFalse(future.isCladironHealthBackupEligible)
    }

    func testBackupEligibility() {
        let authored = CardioWorkout(source: .watch)
        XCTAssertTrue(authored.isCladironHealthBackupEligible)
        let imported = CardioWorkout(source: .watch)
        imported.originValue = .healthKitImported
        XCTAssertFalse(imported.isCladironHealthBackupEligible)
        XCTAssertNil(HealthBackupEncoder.cardioBackupSummary(for: imported))
        XCTAssertNotNil(HealthBackupEncoder.cardioBackupSummary(for: authored))
        // Documented policy: manually logged rows are not backed up.
        XCTAssertFalse(CardioWorkout(isLogged: true).isCladironHealthBackupEligible)
    }

    func testIngestMarksImportedAndExportRoundTrips() throws {
        let ctx = try makeStore()
        let w = IngestedWorkout(id: UUID(), type: .run, start: Date(timeIntervalSince1970: 1000),
                                end: Date(timeIntervalSince1970: 2000), source: .watch,
                                importedKind: .running, provenance: full)
        try WorkoutRepository.ingest([w], in: ctx)
        let row = try XCTUnwrap(try ctx.fetch(FetchDescriptor<CardioWorkout>()).first)
        XCTAssertEqual(row.originValue, .healthKitImported)
        XCTAssertEqual(row.healthKitProvenance, full)
        XCTAssertFalse(row.isCladironHealthBackupEligible)

        let export = try WorkoutRepository.buildExport(ctx)
        let other = try makeStore()
        _ = try WorkoutRepository.merge(export, in: other)
        let copy = try XCTUnwrap(try other.fetch(FetchDescriptor<CardioWorkout>()).first)
        XCTAssertEqual(copy.originValue, .healthKitImported)
        XCTAssertEqual(copy.healthKitProvenance, full)
    }
}
