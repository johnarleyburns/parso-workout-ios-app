#if canImport(SwiftData)
import Foundation
import Testing
import SwiftData
@testable import CadenceCore

@MainActor
struct ExerciseSuggestionExclusionTests {
    @Test func stableKeysPreferSourceIDAndSeparateCustomExercises() {
        let builtIn = Exercise(name: "Bench Press", sourceExerciseID: "bench-v1")
        let custom = Exercise(name: "My Press", isCustom: true)

        #expect(ExerciseSuggestionExclusionKey.forExercise(builtIn) == "dbpp:bench-v1")
        #expect(ExerciseSuggestionExclusionKey.forExercise(custom) ==
                       "custom:\(custom.id.uuidString.lowercased())")
    }

    @Test func exclusionFiltersNamespacedAndLegacyCandidateIDs() {
        let candidates = [
            SuggestedExerciseCandidate(id: "dbpp:bench-v1", name: "Bench Press",
                                       mechanics: .compound, primaryMuscles: ["chest"]),
            SuggestedExerciseCandidate(id: "other", name: "Other",
                                       mechanics: .compound, primaryMuscles: ["chest"])
        ]

        let filtered = SuggestedExerciseFilter.excluding(candidates, keys: ["dbpp:bench-v1"])
        #expect(filtered.map(\.id) == ["other"])

        let legacyFiltered = SuggestedExerciseFilter.excluding(
            [SuggestedExerciseCandidate(id: "bench-v1", name: "Bench Press",
                                        mechanics: .compound, primaryMuscles: ["chest"])],
            keys: ["dbpp:bench-v1"])
        #expect(legacyFiltered.isEmpty)
    }

    @Test func storeReactivatesAndAllowsAnExclusionWithoutDeletingItsTombstone() throws {
        let context = ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
        let exercise = Exercise(name: "Bench Press", sourceExerciseID: "bench-v1")
        context.insert(exercise)
        try context.save()

        let first = try ExerciseSuggestionExclusionStore.setExcluded(
            exercise: exercise, reason: .notAtGym, in: context)
        #expect(try ExerciseSuggestionExclusionStore.active(in: context).count == 1)
        #expect(first.reason == .notAtGym)

        try ExerciseSuggestionExclusionStore.allow(first, in: context)
        #expect(try ExerciseSuggestionExclusionStore.active(in: context).isEmpty)

        let reactivated = try ExerciseSuggestionExclusionStore.setExcluded(
            exercise: exercise, reason: .personalPreference, in: context)
        #expect(reactivated.id == first.id)
        #expect(reactivated.reason == .personalPreference)
        #expect(reactivated.isActive)
        #expect(try context.fetch(FetchDescriptor<ExerciseSuggestionExclusion>()).count == 1)
    }
}
#endif
