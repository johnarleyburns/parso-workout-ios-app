import XCTest
import CadenceCore
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

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

    func testMountainClimbersAreBodyweightWithoutAnExternalLoad() {
        let exercise = Exercise(name: "Mountain Climbers")
        XCTAssertTrue(SessionViewModel.isNonWeighted(exercise))
        let entry = SessionViewModel.normalizedSetEntry(exercise: exercise, requestedWeightKg: 20, requestedUsesBodyweight: false)
        XCTAssertEqual(entry.weightKg, 0)
        XCTAssertTrue(entry.usesBodyweight)
    }
}
