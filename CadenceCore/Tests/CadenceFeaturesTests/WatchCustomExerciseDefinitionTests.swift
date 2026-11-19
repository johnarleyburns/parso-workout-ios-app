import Testing
import CadenceCore
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

struct WatchCustomExerciseDefinitionTests {
    @Test func muscleGroupPillsMapToStableCategories() {
        let muscles = WatchCustomExerciseDefinition.primaryMuscles(for: [.chest, .biceps])
        #expect(muscles == ["chest", "biceps"])
    }

    @Test func oneMovementFamilyGetsUsefulCategory() {
        #expect(WatchCustomExerciseDefinition.category(for: [.lats, .biceps]) == .pull)
        #expect(WatchCustomExerciseDefinition.category(for: [.quadriceps, .calves]) == .legs)
    }

    @Test func mixedMovementFamiliesRemainOther() {
        #expect(WatchCustomExerciseDefinition.category(for: [.chest, .quadriceps]) == .other)
        #expect(WatchCustomExerciseDefinition.category(for: []) == .other)
    }

    @Test func catalogIsTheExactSharedCanonicalMuscleCatalog() {
        #expect(WatchCustomExerciseMuscleAttribution.availableGroups == MuscleGroup.canonicalOrder)
        #expect(Set(WatchCustomExerciseMuscleAttribution.availableGroups) == Set(MuscleGroup.allCases))
        #expect(WatchCustomExerciseMuscleAttribution.availableGroups.count == MuscleGroup.allCases.count)
        for group in MuscleGroup.allCases {
            #expect(WatchCustomExerciseMuscleAttribution.availableGroups.contains(group))
        }
    }

    @Test func roleSelectionMakesNewlyChosenRoleWinAndNeverOverlaps() {
        var attribution = WatchCustomExerciseMuscleAttribution(primary: [.chest], secondary: [.triceps])
        attribution.select(.chest, as: .secondary)
        #expect(!attribution.primary.contains(.chest))
        #expect(attribution.secondary.contains(.chest))
        #expect(attribution.primary.isDisjoint(with: attribution.secondary))

        attribution.select(.chest, as: .primary)
        #expect(attribution.primary.contains(.chest))
        #expect(!attribution.secondary.contains(.chest))
    }

    @Test func persistedArraysAreCanonicalAndKeepPrimaryAndSecondarySeparate() {
        let attribution = WatchCustomExerciseMuscleAttribution(
            primary: [.triceps, .chest], secondary: [.shoulders, .triceps])
        #expect(attribution.primaryIDs == ["chest", "triceps"])
        #expect(attribution.secondaryIDs == ["shoulders"])
    }

    @Test func categoryUsesPrimaryGroupsOnly() {
        let attribution = WatchCustomExerciseMuscleAttribution(primary: [.chest], secondary: [.quadriceps])
        #expect(WatchCustomExerciseDefinition.category(for: attribution.primary) == .push)
    }

    @Test func primaryIsRequired() {
        #expect(!WatchCustomExerciseMuscleAttribution(secondary: [.chest]).hasPrimaryMuscle)
        #expect(WatchCustomExerciseMuscleAttribution(primary: [.chest]).hasPrimaryMuscle)
    }
}
