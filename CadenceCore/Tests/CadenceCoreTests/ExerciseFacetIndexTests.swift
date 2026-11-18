import Testing
@testable import CadenceCore

/// Pure tests for the picker's equipment sub-filter index (feedback: fast
/// equipment narrowing under a selected muscle group).
struct ExerciseFacetIndexTests {

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

    @Test func equipmentPresentIsDedupedAndCanonicalOrder() {
        let shoulders = catalog.filter { $0.trainedMuscleGroups.contains(.shoulders) }
        let equip = ExerciseFacetIndex.equipmentPresent(in: shoulders)
        // Deduped (two dumbbells → one) and in Equipment.allCases order:
        // barbell, dumbbell, cable, ...
        #expect(equip == [.barbell, .dumbbell, .cable])
    }

    @Test func equipmentPresentIgnoresUntagged() {
        let abs = catalog.filter { $0.trainedMuscleGroups.contains(.abdominals) }
        #expect(ExerciseFacetIndex.equipmentPresent(in: abs) == [])
    }

    @Test func equipmentForMuscleGroup() {
        let index = ExerciseFacetIndex(catalog)
        #expect(index.equipment(for: .shoulders) == [.barbell, .dumbbell, .cable])
        #expect(index.equipment(for: .chest) == [.barbell, .bodyweight])
        #expect(index.equipment(for: .quadriceps) == [])   // no leg movements
    }

    @Test func exercisesForPartUnfilteredReturnsAll() {
        let index = ExerciseFacetIndex(catalog)
        #expect(index.exercises(for: .shoulders).count == 4)
    }

    @Test func exercisesForPartNarrowsByEquipment() {
        let index = ExerciseFacetIndex(catalog)
        let db = index.exercises(for: .shoulders, equipment: .dumbbell)
        #expect(db.count == 2)
        #expect(db.allSatisfy { $0.equipmentValue == .dumbbell })

        let barbell = index.exercises(for: .shoulders, equipment: .barbell)
        #expect(barbell.count == 1)
    }

    @Test func exercisesForPartWithAbsentEquipmentIsEmpty() {
        let index = ExerciseFacetIndex(catalog)
        // Shoulders has no bodyweight movement in this catalog.
        #expect(index.exercises(for: .shoulders, equipment: .bodyweight) == [])
    }

    @Test func unknownPartIsEmpty() {
        let index = ExerciseFacetIndex(catalog)
        #expect(index.exercises(for: .calves).count == 0)
        #expect(index.equipment(for: .calves) == [])
    }

    @Test func multiPartExerciseIndexedUnderEachPart() {
        let index = ExerciseFacetIndex(catalog)
        // The bodyweight push-up trains chest + triceps.
        #expect(index.exercises(for: .chest, equipment: .bodyweight).count == 1)
        #expect(index.exercises(for: .triceps, equipment: .bodyweight).count == 1)
    }

    @Test func builtInCatalogShouldersHaveMultipleEquipment() {
        // Guards the real seeded library still gives the sub-filter something to do
        // for a heavily-populated part (drives the UI test's Shoulders → Dumbbell).
        let items = ExerciseLibrary.starter.map {
            Item(trainedMuscleGroups: ExerciseLibrary.muscleGroups(of: $0), equipmentValue: $0.equipment)
        }
        let index = ExerciseFacetIndex(items)
        let shoulderEquip = index.equipment(for: .shoulders)
        #expect(shoulderEquip.contains(.dumbbell), "shoulders should include dumbbell movements")
        #expect(shoulderEquip.count > 1, "shoulders should offer more than one equipment type")
    }
}
