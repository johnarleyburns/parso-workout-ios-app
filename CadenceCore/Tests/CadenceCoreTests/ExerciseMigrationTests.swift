#if canImport(SwiftData)
import Foundation
import Testing
import SwiftData
@testable import CadenceCore

/// The DB++ adoption changes the muscle vocabulary stored on every exercise row.
/// These tests cover the migration that gets an existing store there without
/// losing anything the user entered (decision D7).
struct ExerciseMigrationTests {

    private func makeStore() throws -> ModelContext {
        let container = try ModelContainer(
            for: Exercise.self, WorkoutSession.self, SetEntry.self, Person.self,
            Assessment.self, CardioWorkout.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    @Test func legacyIdsAreCanonicalized() throws {
        let ctx = try makeStore()
        let custom = Exercise(name: "Arley's Special", isCustom: true,
                              primaryMuscles: ["quads", "rear-delts"],
                              secondaryMuscles: ["abs"])
        ctx.insert(custom)
        try ctx.save()

        try WorkoutRepository.seedStarterLibraryIfNeeded(ctx)

        #expect(custom.primaryMuscles == ["quadriceps", "shoulders"])
        #expect(custom.secondaryMuscles == ["abdominals"])
    }

    /// Nothing the user typed is destroyed: the pre-migration ids are parked in the
    /// legacy tag field, so the change is reversible.
    @Test func originalIdsArePreservedInLegacyTags() throws {
        let ctx = try makeStore()
        let custom = Exercise(name: "Arley's Special", isCustom: true,
                              primaryMuscles: ["quads", "rear-delts"],
                              secondaryMuscles: ["abs"])
        ctx.insert(custom)
        try ctx.save()

        try WorkoutRepository.seedStarterLibraryIfNeeded(ctx)

        #expect(custom.muscleGroups == ["quads", "rear-delts", "abs"])
    }

    @Test func migrationDoesNotTouchAlreadyCanonicalRows() throws {
        let ctx = try makeStore()
        let custom = Exercise(name: "Already Fine", isCustom: true,
                              primaryMuscles: ["quadriceps"], secondaryMuscles: ["glutes"])
        ctx.insert(custom)
        try ctx.save()
        let before = custom.updatedAt

        #expect(!WorkoutRepository.canonicalizeStoredMuscleIDs([custom]))
        #expect(custom.updatedAt == before)
        #expect(custom.muscleGroups.isEmpty, "nothing to preserve, nothing written")
    }

    @Test func seedingIsIdempotent() throws {
        let ctx = try makeStore()
        #expect(try WorkoutRepository.seedStarterLibraryIfNeeded(ctx))
        #expect(!(try WorkoutRepository.seedStarterLibraryIfNeeded(ctx)),
                       "a second seed must be a no-op")
    }

    @Test func builtInsGetTheAnnotation() throws {
        let ctx = try makeStore()
        try WorkoutRepository.seedStarterLibraryIfNeeded(ctx)

        let squat = try #require(try WorkoutRepository.allExercises(ctx)
            .first { $0.name == "Back Squat" })
        #expect(squat.directMuscles == [.quadriceps, .glutes])
        #expect(squat.indirectMuscles == [.adductors])
        #expect(squat.stabilizerMuscles.contains(.lowerBack))
        #expect(squat.volumeEligible)
        #expect(squat.annotationConfidenceValue == .high)
        #expect(squat.sourceExerciseID == "Barbell_Squat")
        #expect(squat.movementPatternIDs == ["squat"])
        #expect(squat.trainingTypes == [.strength])
    }

    /// The headline behaviour change: a stabiliser earns no weekly volume.
    @Test func stabilizersEarnNoCredit() throws {
        let ctx = try makeStore()
        try WorkoutRepository.seedStarterLibraryIfNeeded(ctx)

        let deadlift = try #require(try WorkoutRepository.allExercises(ctx)
            .first { $0.name == "Deadlift" })
        #expect(deadlift.setCredit(for: .glutes) == 1.0)
        #expect(deadlift.setCredit(for: .hamstrings) == 1.0)
        #expect(deadlift.setCredit(for: .quadriceps) == 0.5)
        #expect(deadlift.setCredit(for: .lowerBack) == 0.0,
                       "the lower back stabilises a deadlift; it is not trained by it")
    }

    /// A custom exercise has no DB++ annotation, so its credit falls back to the
    /// primary/secondary lists the user gave it.
    @Test func customExerciseVolumeCreditFallsBackToPrimarySecondary() throws {
        let custom = Exercise(name: "Arley's Special", isCustom: true,
                              primaryMuscles: ["quads"], secondaryMuscles: ["glutes"])
        #expect(custom.setCredit(for: .quadriceps) == 1.0)
        #expect(custom.setCredit(for: .glutes) == 0.5)
        #expect(custom.setCredit(for: .chest) == 0.0)
        #expect(custom.annotationConfidenceValue == nil,
                     "nil confidence is what tells the UI these roles are not evidence-backed")
    }

    @Test func nonVolumeExerciseCreditsNothing() throws {
        let ctx = try makeStore()
        try WorkoutRepository.seedStarterLibraryIfNeeded(ctx)

        let stretch = try #require(try WorkoutRepository.allExercises(ctx)
            .first { $0.trainingTypes.contains(.stretching) })
        #expect(!stretch.volumeEligible)
        #expect(stretch.volumeCredits.isEmpty)
        #expect(!stretch.primaryMuscles.isEmpty, "it stays browsable by muscle")
    }

    @Test func everyStoredMuscleIdIsCanonicalAfterSeeding() throws {
        let ctx = try makeStore()
        try WorkoutRepository.seedStarterLibraryIfNeeded(ctx)

        for ex in try WorkoutRepository.allExercises(ctx) {
            for id in ex.primaryMuscles + ex.secondaryMuscles {
                #expect(MuscleGroup(rawValue: id) != nil,
                                "\(ex.name) stores non-canonical muscle id \(id)")
            }
        }
    }
}

/// Current export carries the annotation; older files still import unchanged.
struct ExportAnnotationRoundTripTests {

    private func makeStore() throws -> ModelContext {
        let container = try ModelContainer(
            for: Exercise.self, WorkoutSession.self, SetEntry.self, Person.self,
            Assessment.self, CardioWorkout.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    @Test func currentExportRoundTripPreservesTheAnnotation() throws {
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
        #expect(export.version == CadenceExport.currentVersion)
        let decoded = try DataExport.decodeJSON(try DataExport.encodeJSON(export))

        let newCtx = try makeStore()
        try WorkoutRepository.merge(decoded, in: newCtx)
        let imported = try #require(try WorkoutRepository.allExercises(newCtx)
            .first { $0.name == "Annotated Custom" })

        #expect(imported.directMuscles == [.chest])
        #expect(imported.indirectMuscles == [.triceps])
        #expect(imported.stabilizerMuscles == [.abdominals])
        #expect(imported.trainingTypes == [.strength])
        #expect(imported.modalities == [.freeWeight])
        #expect(imported.movementPatternIDs == ["horizontal_press"])
        #expect(imported.annotationConfidenceValue == .high)
        #expect(imported.sourceExerciseID == "Some_Id")
        #expect(imported.volumeEligible)
    }

    /// A file written before the annotation existed decodes with every new field
    /// absent, and imports to a working exercise with sane defaults.
    @Test func preV6ExportImportsWithDefaultsAndCanonicalMuscles() throws {
        let legacy = CadenceExport(
            version: 5, sessions: [], cardio: [], assessments: [],
            exercises: [ExportExercise(id: UUID(), name: "Legacy Custom",
                                       primaryMuscles: ["quads"],
                                       secondaryMuscles: ["rear-delts"])])
        let decoded = try DataExport.decodeJSON(try DataExport.encodeJSON(legacy))
        #expect(decoded.exercises.first?.volumeEligible == nil)
        #expect(decoded.exercises.first?.directMuscles == nil)

        let ctx = try makeStore()
        try WorkoutRepository.merge(decoded, in: ctx)
        let imported = try #require(try WorkoutRepository.allExercises(ctx)
            .first { $0.name == "Legacy Custom" })
        #expect(imported.primaryMuscles == ["quadriceps"])
        #expect(imported.secondaryMuscles == ["shoulders"])
        #expect(imported.volumeEligible, "an unannotated import still counts")
        #expect(imported.setCredit(for: .quadriceps) == 1.0)
    }
}
#endif
