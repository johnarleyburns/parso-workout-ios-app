import XCTest
@testable import CadenceCore

/// Pure tests for the picker's equipment sub-filter index (feedback: fast
/// equipment narrowing under a selected muscle group).
final class ExerciseFacetIndexTests: XCTestCase {

    private struct Item: EquipmentClassifiable, Equatable {
        var trainedMuscleGroups: Set<MuscleGroup>
        var equipmentValue: Equipment?
    }

    private var catalog: [Item] {
        [
            Item(trainedMuscleGroups: [.shoulders], equipmentValue: .barbell),   // Overhead Press
            Item(trainedMuscleGroups: [.shoulders], equipmentValue: .dumbbell),  // DB Shoulder Press
            Item(trainedMuscleGroups: [.shoulders], equipmentValue: .dumbbell),  // Lateral Raise
            Item(trainedMuscleGroups: [.shoulders], equipmentValue: .cable),     // Cable Lateral Raise
            Item(trainedMuscleGroups: [.chest, .triceps], equipmentValue: .bodyweight), // Push-Up
            Item(trainedMuscleGroups: [.chest], equipmentValue: .barbell),       // Bench Press
            Item(trainedMuscleGroups: [.abdominals], equipmentValue: nil),              // untagged
        ]
    }

    func testEquipmentPresentIsDedupedAndCanonicalOrder() {
        let shoulders = catalog.filter { $0.trainedMuscleGroups.contains(.shoulders) }
        let equip = ExerciseFacetIndex.equipmentPresent(in: shoulders)
        // Deduped (two dumbbells → one) and in Equipment.allCases order:
        // barbell, dumbbell, cable, ...
        XCTAssertEqual(equip, [.barbell, .dumbbell, .cable])
    }

    func testEquipmentPresentIgnoresUntagged() {
        let abs = catalog.filter { $0.trainedMuscleGroups.contains(.abdominals) }
        XCTAssertEqual(ExerciseFacetIndex.equipmentPresent(in: abs), [])
    }

    func testEquipmentForMuscleGroup() {
        let index = ExerciseFacetIndex(catalog)
        XCTAssertEqual(index.equipment(for: .shoulders), [.barbell, .dumbbell, .cable])
        XCTAssertEqual(index.equipment(for: .chest), [.barbell, .bodyweight])
        XCTAssertEqual(index.equipment(for: .quadriceps), [])   // no leg movements
    }

    func testExercisesForPartUnfilteredReturnsAll() {
        let index = ExerciseFacetIndex(catalog)
        XCTAssertEqual(index.exercises(for: .shoulders).count, 4)
    }

    func testExercisesForPartNarrowsByEquipment() {
        let index = ExerciseFacetIndex(catalog)
        let db = index.exercises(for: .shoulders, equipment: .dumbbell)
        XCTAssertEqual(db.count, 2)
        XCTAssertTrue(db.allSatisfy { $0.equipmentValue == .dumbbell })

        let barbell = index.exercises(for: .shoulders, equipment: .barbell)
        XCTAssertEqual(barbell.count, 1)
    }

    func testExercisesForPartWithAbsentEquipmentIsEmpty() {
        let index = ExerciseFacetIndex(catalog)
        // Shoulders has no bodyweight movement in this catalog.
        XCTAssertEqual(index.exercises(for: .shoulders, equipment: .bodyweight), [])
    }

    func testUnknownPartIsEmpty() {
        let index = ExerciseFacetIndex(catalog)
        XCTAssertEqual(index.exercises(for: .calves).count, 0)
        XCTAssertEqual(index.equipment(for: .calves), [])
    }

    func testMultiPartExerciseIndexedUnderEachPart() {
        let index = ExerciseFacetIndex(catalog)
        // The bodyweight push-up trains chest + triceps.
        XCTAssertTrue(index.exercises(for: .chest, equipment: .bodyweight).count == 1)
        XCTAssertTrue(index.exercises(for: .triceps, equipment: .bodyweight).count == 1)
    }

    func testBuiltInCatalogShouldersHaveMultipleEquipment() {
        // Guards the real seeded library still gives the sub-filter something to do
        // for a heavily-populated part (drives the UI test's Shoulders → Dumbbell).
        let items = ExerciseLibrary.starter.map {
            Item(trainedMuscleGroups: ExerciseLibrary.muscleGroups(of: $0), equipmentValue: $0.equipment)
        }
        let index = ExerciseFacetIndex(items)
        let shoulderEquip = index.equipment(for: .shoulders)
        XCTAssertTrue(shoulderEquip.contains(.dumbbell), "shoulders should include dumbbell movements")
        XCTAssertGreaterThan(shoulderEquip.count, 1, "shoulders should offer more than one equipment type")
    }
}
