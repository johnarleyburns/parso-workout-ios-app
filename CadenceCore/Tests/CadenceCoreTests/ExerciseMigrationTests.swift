import XCTest
import SwiftData
@testable import CadenceCore

/// The DB++ adoption changes the muscle vocabulary stored on every exercise row.
/// These tests cover the migration that gets an existing store there without
/// losing anything the user entered (decision D7).
final class ExerciseMigrationTests: XCTestCase {

    private func makeStore() throws -> ModelContext {
        let container = try ModelContainer(
            for: Exercise.self, WorkoutSession.self, SetEntry.self, Person.self,
            Assessment.self, CardioWorkout.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    func testLegacyIdsAreCanonicalized() throws {
        let ctx = try makeStore()
        let custom = Exercise(name: "Arley's Special", isCustom: true,
                              primaryMuscles: ["quads", "rear-delts"],
                              secondaryMuscles: ["abs"])
        ctx.insert(custom)
        try ctx.save()

        try WorkoutRepository.seedStarterLibraryIfNeeded(ctx)

        XCTAssertEqual(custom.primaryMuscles, ["quadriceps", "shoulders"])
        XCTAssertEqual(custom.secondaryMuscles, ["abdominals"])
    }

    /// Nothing the user typed is destroyed: the pre-migration ids are parked in the
    /// legacy tag field, so the change is reversible.
    func testOriginalIdsArePreservedInLegacyTags() throws {
        let ctx = try makeStore()
        let custom = Exercise(name: "Arley's Special", isCustom: true,
                              primaryMuscles: ["quads", "rear-delts"],
                              secondaryMuscles: ["abs"])
        ctx.insert(custom)
        try ctx.save()

        try WorkoutRepository.seedStarterLibraryIfNeeded(ctx)

        XCTAssertEqual(custom.muscleGroups, ["quads", "rear-delts", "abs"])
    }

    func testMigrationDoesNotTouchAlreadyCanonicalRows() throws {
        let ctx = try makeStore()
        let custom = Exercise(name: "Already Fine", isCustom: true,
                              primaryMuscles: ["quadriceps"], secondaryMuscles: ["glutes"])
        ctx.insert(custom)
        try ctx.save()
        let before = custom.updatedAt

        XCTAssertFalse(WorkoutRepository.canonicalizeStoredMuscleIDs([custom]))
        XCTAssertEqual(custom.updatedAt, before)
        XCTAssertTrue(custom.muscleGroups.isEmpty, "nothing to preserve, nothing written")
    }

    func testSeedingIsIdempotent() throws {
        let ctx = try makeStore()
        XCTAssertTrue(try WorkoutRepository.seedStarterLibraryIfNeeded(ctx))
        XCTAssertFalse(try WorkoutRepository.seedStarterLibraryIfNeeded(ctx),
                       "a second seed must be a no-op")
    }

    func testBuiltInsGetTheAnnotation() throws {
        let ctx = try makeStore()
        try WorkoutRepository.seedStarterLibraryIfNeeded(ctx)

        let squat = try XCTUnwrap(try WorkoutRepository.allExercises(ctx)
            .first { $0.name == "Back Squat" })
        XCTAssertEqual(squat.directMuscles, [.quadriceps, .glutes])
        XCTAssertEqual(squat.indirectMuscles, [.adductors])
        XCTAssertTrue(squat.stabilizerMuscles.contains(.lowerBack))
        XCTAssertTrue(squat.volumeEligible)
        XCTAssertEqual(squat.annotationConfidenceValue, .high)
        XCTAssertEqual(squat.sourceExerciseID, "Barbell_Squat")
        XCTAssertEqual(squat.movementPatternIDs, ["squat"])
        XCTAssertEqual(squat.trainingTypes, [.strength])
    }

    /// The headline behaviour change: a stabiliser earns no weekly volume.
    func testStabilizersEarnNoCredit() throws {
        let ctx = try makeStore()
        try WorkoutRepository.seedStarterLibraryIfNeeded(ctx)

        let deadlift = try XCTUnwrap(try WorkoutRepository.allExercises(ctx)
            .first { $0.name == "Deadlift" })
        XCTAssertEqual(deadlift.setCredit(for: .glutes), 1.0)
        XCTAssertEqual(deadlift.setCredit(for: .hamstrings), 1.0)
        XCTAssertEqual(deadlift.setCredit(for: .quadriceps), 0.5)
        XCTAssertEqual(deadlift.setCredit(for: .lowerBack), 0.0,
                       "the lower back stabilises a deadlift; it is not trained by it")
    }

    /// A custom exercise has no DB++ annotation, so its credit falls back to the
    /// primary/secondary lists the user gave it.
    func testCustomExerciseVolumeCreditFallsBackToPrimarySecondary() throws {
        let custom = Exercise(name: "Arley's Special", isCustom: true,
                              primaryMuscles: ["quads"], secondaryMuscles: ["glutes"])
        XCTAssertEqual(custom.setCredit(for: .quadriceps), 1.0)
        XCTAssertEqual(custom.setCredit(for: .glutes), 0.5)
        XCTAssertEqual(custom.setCredit(for: .chest), 0.0)
        XCTAssertNil(custom.annotationConfidenceValue,
                     "nil confidence is what tells the UI these roles are not evidence-backed")
    }

    func testNonVolumeExerciseCreditsNothing() throws {
        let ctx = try makeStore()
        try WorkoutRepository.seedStarterLibraryIfNeeded(ctx)

        let stretch = try XCTUnwrap(try WorkoutRepository.allExercises(ctx)
            .first { $0.trainingTypes.contains(.stretching) })
        XCTAssertFalse(stretch.volumeEligible)
        XCTAssertTrue(stretch.volumeCredits.isEmpty)
        XCTAssertFalse(stretch.primaryMuscles.isEmpty, "it stays browsable by muscle")
    }

    func testEveryStoredMuscleIdIsCanonicalAfterSeeding() throws {
        let ctx = try makeStore()
        try WorkoutRepository.seedStarterLibraryIfNeeded(ctx)

        for ex in try WorkoutRepository.allExercises(ctx) {
            for id in ex.primaryMuscles + ex.secondaryMuscles {
                XCTAssertNotNil(MuscleGroup(rawValue: id),
                                "\(ex.name) stores non-canonical muscle id \(id)")
            }
        }
    }
}

/// Export v6 carries the annotation; older files still import unchanged.
final class ExportAnnotationRoundTripTests: XCTestCase {

    private func makeStore() throws -> ModelContext {
        let container = try ModelContainer(
            for: Exercise.self, WorkoutSession.self, SetEntry.self, Person.self,
            Assessment.self, CardioWorkout.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    func testV6RoundTripPreservesTheAnnotation() throws {
        let ctx = try makeStore()
        let custom = Exercise(name: "Annotated Custom", isCustom: true,
                              primaryMuscles: ["chest"], secondaryMuscles: ["triceps"],
                              directMuscles: [.chest], indirectMuscles: [.triceps],
                              stabilizerMuscles: [.abdominals],
                              trainingTypes: [.strength], modalities: [.freeWeight],
                              sportContexts: [.generalFitness],
                              movementPatternIDs: ["horizontal_press"],
                              volumeEligible: true, annotationConfidence: .high,
                              sourceExerciseID: "Some_Id")
        ctx.insert(custom)
        try ctx.save()

        let export = try WorkoutRepository.buildExport(ctx)
        XCTAssertEqual(export.version, 6)
        let decoded = try DataExport.decodeJSON(try DataExport.encodeJSON(export))

        let newCtx = try makeStore()
        try WorkoutRepository.merge(decoded, in: newCtx)
        let imported = try XCTUnwrap(try WorkoutRepository.allExercises(newCtx)
            .first { $0.name == "Annotated Custom" })

        XCTAssertEqual(imported.directMuscles, [.chest])
        XCTAssertEqual(imported.indirectMuscles, [.triceps])
        XCTAssertEqual(imported.stabilizerMuscles, [.abdominals])
        XCTAssertEqual(imported.trainingTypes, [.strength])
        XCTAssertEqual(imported.modalities, [.freeWeight])
        XCTAssertEqual(imported.movementPatternIDs, ["horizontal_press"])
        XCTAssertEqual(imported.annotationConfidenceValue, .high)
        XCTAssertEqual(imported.sourceExerciseID, "Some_Id")
        XCTAssertTrue(imported.volumeEligible)
    }

    /// A file written before the annotation existed decodes with every new field
    /// absent, and imports to a working exercise with sane defaults.
    func testPreV6ExportImportsWithDefaultsAndCanonicalMuscles() throws {
        let legacy = CadenceExport(
            version: 5, sessions: [], cardio: [], assessments: [],
            exercises: [ExportExercise(id: UUID(), name: "Legacy Custom",
                                       primaryMuscles: ["quads"],
                                       secondaryMuscles: ["rear-delts"])])
        let decoded = try DataExport.decodeJSON(try DataExport.encodeJSON(legacy))
        XCTAssertNil(decoded.exercises.first?.volumeEligible)
        XCTAssertNil(decoded.exercises.first?.directMuscles)

        let ctx = try makeStore()
        try WorkoutRepository.merge(decoded, in: ctx)
        let imported = try XCTUnwrap(try WorkoutRepository.allExercises(ctx)
            .first { $0.name == "Legacy Custom" })
        XCTAssertEqual(imported.primaryMuscles, ["quadriceps"])
        XCTAssertEqual(imported.secondaryMuscles, ["shoulders"])
        XCTAssertTrue(imported.volumeEligible, "an unannotated import still counts")
        XCTAssertEqual(imported.setCredit(for: .quadriceps), 1.0)
    }
}
