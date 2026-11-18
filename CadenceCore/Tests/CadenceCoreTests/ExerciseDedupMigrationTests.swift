import XCTest
import SwiftData
@testable import CadenceCore

/// Existing installs that already seeded both the empty "Handstand Push-Up" stub
/// and the full "Handstand Push-Ups" must collapse to a single row on next launch,
/// preserving logged sets and the favorite flag. Custom exercises are untouched.
final class ExerciseDedupMigrationTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    func testCollapsesDuplicateBuiltInsPreservingSetsAndFavorite() throws {
        let ctx = try makeContext()

        // Empty stub (canonical name) + full imported twin (plural), as a prior seed
        // would have produced.
        let stub = Exercise(name: "Handstand Push-Up", category: .push,
                            equipment: .bodyweight, mechanics: .compound, force: .push)
        let full = Exercise(name: "Handstand Push-Ups", category: .push,
                            equipment: .bodyweight, mechanics: .compound, force: .push,
                            instructions: ["Kick up", "Lower", "Press"], imageName: "Handstand_Push-Ups")
        full.isFavorite = true
        ctx.insert(stub); ctx.insert(full)

        // A logged set against the (to-be-deleted) plural twin must survive.
        let set = SetEntry(weight: 0, reps: 5, usesBodyweight: true, exercise: full)
        ctx.insert(set)
        try ctx.save()

        let changed = try WorkoutRepository.collapseDuplicateBuiltInExercises(ctx)
        XCTAssertTrue(changed)

        let remaining = try WorkoutRepository.allExercises(ctx)
        XCTAssertEqual(remaining.count, 1, "the two rows collapse to one")
        let survivor = remaining[0]
        XCTAssertEqual(survivor.name, "Handstand Push-Up", "canonical library name survives")
        XCTAssertFalse(survivor.instructions.isEmpty, "instructions carried over from the twin")
        XCTAssertEqual(survivor.imageName, "Handstand_Push-Ups")
        XCTAssertTrue(survivor.isFavorite, "favorite flag transferred")
        XCTAssertEqual(survivor.sets?.count, 1, "the logged set was repointed, not orphaned")
        XCTAssertEqual(survivor.sets?.first?.id, set.id)
    }

    func testIsIdempotent() throws {
        let ctx = try makeContext()
        let a = Exercise(name: "Ring Dip", category: .push, equipment: .bodyweight, mechanics: .compound, force: .push)
        let b = Exercise(name: "Ring Dips", category: .push, equipment: .bodyweight, mechanics: .compound, force: .push,
                         instructions: ["Support", "Dip"])
        ctx.insert(a); ctx.insert(b)
        try ctx.save()

        XCTAssertTrue(try WorkoutRepository.collapseDuplicateBuiltInExercises(ctx))
        XCTAssertFalse(try WorkoutRepository.collapseDuplicateBuiltInExercises(ctx),
                       "second run is a no-op")
        XCTAssertEqual(try WorkoutRepository.allExercises(ctx).count, 1)
    }

    func testDoesNotTouchCustomExercises() throws {
        let ctx = try makeContext()
        // A built-in and a same-key CUSTOM entry the user created — must NOT merge.
        let builtIn = Exercise(name: "Mountain Climbers", category: .core, equipment: .bodyweight,
                               mechanics: .compound, force: .push, instructions: ["Go"])
        let custom = Exercise(name: "Mountain Climber", category: .core, isCustom: true,
                              equipment: .bodyweight, mechanics: .compound, force: .push)
        ctx.insert(builtIn); ctx.insert(custom)
        try ctx.save()

        XCTAssertFalse(try WorkoutRepository.collapseDuplicateBuiltInExercises(ctx),
                       "custom entries are never collapsed")
        XCTAssertEqual(try WorkoutRepository.allExercises(ctx).count, 2)
    }
}
