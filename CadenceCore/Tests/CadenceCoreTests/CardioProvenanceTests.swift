#if canImport(SwiftData)
import Testing
import SwiftData
@testable import CadenceCore

struct CardioProvenanceTests {
    private func makeStore() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    private let full = HealthKitWorkoutProvenance(
        sourceName: "Strava", sourceBundleIdentifier: "com.strava", sourceVersion: "1",
        productType: "Watch7,1", deviceName: "Apple Watch", deviceManufacturer: "Apple Inc.",
        deviceModel: "Watch", deviceHardwareVersion: "Watch7,1", deviceSoftwareVersion: "11.0",
        workoutBrandName: "Peloton", isAppleFitnessPlus: true)

    @Test func provenanceRoundTripsFullAndEmpty() {
        #expect(HealthKitWorkoutProvenance.decode(full.encodedString()) == full)
        let empty = HealthKitWorkoutProvenance(sourceName: "", sourceBundleIdentifier: "")
        #expect(HealthKitWorkoutProvenance.decode(empty.encodedString()) == empty)
        #expect(HealthKitWorkoutProvenance.decode("") == nil)
        #expect(HealthKitWorkoutProvenance.decode("{\"version\":99,\"provenance\":{}}") == nil)
    }

    @Test func legacyAndUnknownOrigins() {
        let legacy = CardioWorkout()
        #expect(legacy.originValue == .cladironRecorded)
        #expect(legacy.recordOriginRaw == nil, "reading must not mutate")
        let kind = CardioWorkout(importedWorkoutKind: .running)
        #expect(kind.originValue == .healthKitImported)
        let future = CardioWorkout()
        future.recordOriginRaw = "someFutureOrigin"
        #expect(future.originValue == .unrecognized)
        #expect(!future.isCladironHealthBackupEligible)
    }

    @Test func backupEligibility() {
        let authored = CardioWorkout(source: .watch)
        #expect(authored.isCladironHealthBackupEligible)
        let imported = CardioWorkout(source: .watch)
        imported.originValue = .healthKitImported
        #expect(!imported.isCladironHealthBackupEligible)
        #expect(HealthBackupEncoder.cardioBackupSummary(for: imported) == nil)
        #expect(HealthBackupEncoder.cardioBackupSummary(for: authored) != nil)
        // Documented policy: manually logged rows are not backed up.
        #expect(!CardioWorkout(isLogged: true).isCladironHealthBackupEligible)
    }

    @Test func ingestMarksImportedAndExportRoundTrips() throws {
        let ctx = try makeStore()
        let w = IngestedWorkout(id: UUID(), type: .run, start: Date(timeIntervalSince1970: 1000),
                                end: Date(timeIntervalSince1970: 2000), source: .watch,
                                importedKind: .running, provenance: full)
        try WorkoutRepository.ingest([w], in: ctx)
        let row = try #require(try ctx.fetch(FetchDescriptor<CardioWorkout>()).first)
        #expect(row.originValue == .healthKitImported)
        #expect(row.healthKitProvenance == full)
        #expect(!row.isCladironHealthBackupEligible)

        let export = try WorkoutRepository.buildExport(ctx)
        let other = try makeStore()
        _ = try WorkoutRepository.merge(export, in: other)
        let copy = try #require(try other.fetch(FetchDescriptor<CardioWorkout>()).first)
        #expect(copy.originValue == .healthKitImported)
        #expect(copy.healthKitProvenance == full)
    }
}
#endif
