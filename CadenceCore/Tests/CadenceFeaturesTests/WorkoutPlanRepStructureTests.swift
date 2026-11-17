import XCTest
import CadenceCore
@testable import CadenceFeatures

final class WorkoutPlanRepStructureTests: XCTestCase {
    func testApplyingPartnerStructurePreservesOwnerAndOtherPartnerLoads() {
        let partner = UUID()
        let other = UUID()
        let sets = [EditableSet(targetReps: 8, targetWeight: 25)]
        var plan = EditablePlan(warmupMinutes: 0, cooldownMinutes: 0, exercises: ["Squat", "Row"].map {
            EditableExercise(name: $0, sets: sets, notes: "", performerPlans: [
                .init(performerID: nil, name: "Me", sets: sets),
                .init(performerID: partner, name: "Pat", sets: sets),
                .init(performerID: other, name: "Sam", sets: sets)
            ])
        })
        plan.applyRepStructure([12, 10, 8], performerID: partner)
        for exercise in plan.exercises {
            XCTAssertEqual(exercise.sets, sets)
            XCTAssertEqual(exercise.performerPlans[0].sets, sets)
            XCTAssertEqual(exercise.performerPlans[1].sets.map(\.targetReps), [12, 10, 8])
            XCTAssertEqual(exercise.performerPlans[1].sets.map(\.targetWeight), [25, 25, 25])
            XCTAssertEqual(exercise.performerPlans[2].sets, sets)
        }
        XCTAssertEqual(plan.performerPrescriptions().first { $0.performerID == partner.uuidString }?
            .exercises.map { $0.sets.map(\.targetReps) }, [[12, 10, 8], [12, 10, 8]])
        plan.applyRepStructure([5, 5], performerID: nil)
        XCTAssertTrue(plan.exercises.allSatisfy { $0.sets.map(\.targetReps) == [5, 5] && $0.performerPlans[0].sets == $0.sets })
    }

    func testStructureLabelAndSelectionReflectActualSets() {
        let sets = [8, 8, 8].map { EditableSet(targetReps: $0, targetWeight: 25) }
        let plan = EditablePlan(warmupMinutes: 0, cooldownMinutes: 0,
            exercises: [EditableExercise(name: "Row", sets: sets, notes: "")])
        XCTAssertEqual(plan.repStructure(performerID: nil), [8, 8, 8])
        XCTAssertEqual(plan.repStructure(performerID: nil).map(String.init).joined(separator: "-"), "8-8-8")
    }

    func testSuggestedDefaultsRepeatLastWorkingSetAndKeepPlannedCount() {
        let original = (0..<3).map { _ in EditableSet(targetReps: 6, targetWeight: nil) }
        let history = PartnerPlanResolver.ExerciseHistory(lastSets: [
            .init(weightKg: 100, reps: 6), .init(weightKg: 92.98643585, reps: 8)])
        let seeded = PartnerPlanResolver.suggestedOwnerSets(original, history: history)
        XCTAssertEqual(seeded.map(\.id), original.map(\.id))
        XCTAssertEqual(seeded.map(\.targetReps), [8, 8, 8])
        XCTAssertEqual(seeded.map(\.targetWeight), [92.98643585, 92.98643585, 92.98643585])
        XCTAssertEqual(PartnerPlanResolver.suggestedOwnerSets(original, history: .empty), original)
        let explicit = [EditableSet(targetReps: 12, targetWeight: 20)]
        XCTAssertEqual(PartnerPlanResolver.suggestedOwnerSets(explicit, history: history), explicit)
    }

    func testMountainClimbersAreBodyweightWithoutAnExternalLoad() {
        let exercise = Exercise(name: "Mountain Climbers")
        XCTAssertTrue(SessionViewModel.isNonWeighted(exercise))
        let entry = SessionViewModel.normalizedSetEntry(exercise: exercise, requestedWeightKg: 20, requestedUsesBodyweight: false)
        XCTAssertEqual(entry.weightKg, 0)
        XCTAssertTrue(entry.usesBodyweight)
    }
}
