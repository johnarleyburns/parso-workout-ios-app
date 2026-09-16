import XCTest
import SwiftData
@testable import CadenceCore

@MainActor
final class ExerciseSuggestionExclusionTests: XCTestCase {
    func testStableKeysPreferSourceIDAndSeparateCustomExercises() {
        let builtIn = Exercise(name: "Bench Press", sourceExerciseID: "bench-v1")
        let custom = Exercise(name: "My Press", isCustom: true)

        XCTAssertEqual(ExerciseSuggestionExclusionKey.forExercise(builtIn), "dbpp:bench-v1")
        XCTAssertEqual(ExerciseSuggestionExclusionKey.forExercise(custom),
                       "custom:\(custom.id.uuidString.lowercased())")
    }

    func testExclusionFiltersNamespacedAndLegacyCandidateIDs() {
        let candidates = [
            SuggestedExerciseCandidate(id: "dbpp:bench-v1", name: "Bench Press",
                                       mechanics: .compound, primaryMuscles: ["chest"]),
            SuggestedExerciseCandidate(id: "other", name: "Other",
                                       mechanics: .compound, primaryMuscles: ["chest"])
        ]

        let filtered = SuggestedExerciseFilter.excluding(candidates, keys: ["dbpp:bench-v1"])
        XCTAssertEqual(filtered.map(\.id), ["other"])

        let legacyFiltered = SuggestedExerciseFilter.excluding(
            [SuggestedExerciseCandidate(id: "bench-v1", name: "Bench Press",
                                        mechanics: .compound, primaryMuscles: ["chest"])],
            keys: ["dbpp:bench-v1"])
        XCTAssertTrue(legacyFiltered.isEmpty)
    }

    func testStoreReactivatesAndAllowsAnExclusionWithoutDeletingItsTombstone() throws {
        let context = ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
        let exercise = Exercise(name: "Bench Press", sourceExerciseID: "bench-v1")
        context.insert(exercise)
        try context.save()

        let first = try ExerciseSuggestionExclusionStore.setExcluded(
            exercise: exercise, reason: .notAtGym, in: context)
        XCTAssertEqual(try ExerciseSuggestionExclusionStore.active(in: context).count, 1)
        XCTAssertEqual(first.reason, .notAtGym)

        try ExerciseSuggestionExclusionStore.allow(first, in: context)
        XCTAssertTrue(try ExerciseSuggestionExclusionStore.active(in: context).isEmpty)

        let reactivated = try ExerciseSuggestionExclusionStore.setExcluded(
            exercise: exercise, reason: .personalPreference, in: context)
        XCTAssertEqual(reactivated.id, first.id)
        XCTAssertEqual(reactivated.reason, .personalPreference)
        XCTAssertTrue(reactivated.isActive)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ExerciseSuggestionExclusion>()).count, 1)
    }
}
