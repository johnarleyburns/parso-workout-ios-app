#if canImport(SwiftData)
import XCTest
import Foundation
import SwiftData
import CadenceCore
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

final class WorkoutEntryPreferenceTests: XCTestCase {
    func testWatchOverrideBeatsLaterPlanSetsAndExercises() throws {
        let container = try CadenceStore.makeModelContainer(inMemory: true)
        let context = ModelContext(container)
        let model = WatchStrengthFlowModel(context: context, unit: .kilograms,
                                            cooldownDefault: 0, restDefault: 0)
        let names = ["Biceps Curl", "Dumbbell Press"]
        let payload = WatchPlanPayload(strength: .init(exerciseNames: names,
            prescriptions: names.map { name in
                PlannedExercisePrescription(exerciseName: name, sets: [
                    PlannedSetPrescription(targetReps: 6, targetWeightKg: 20),
                    PlannedSetPrescription(targetReps: 6, targetWeightKg: 20)
                ])
            }))
        model.start(title: "Sticky", plannedExerciseNames: names,
                    planPayload: payload, createSession: true)
        let first = try XCTUnwrap(model.exerciseList.first?.exercise)
        model.startLogSet(for: first)
        model.currentReps = 10
        model.currentWeight = 25
        _ = model.logSet()
        model.startLogSet(for: first)
        XCTAssertEqual(model.currentReps, 10)
        XCTAssertEqual(model.currentWeight, 25)
        let second = try XCTUnwrap(model.exerciseList.first { $0.exercise.id != first.id }?.exercise)
        model.startLogSet(for: second)
        XCTAssertEqual(model.currentReps, 10)
        XCTAssertEqual(model.currentWeight, 20)
    }

    func testExplicitRepsStayWithinWorkoutAndPerformer() {
        let workout = WorkoutSession(title: "Workout")
        let partner = UUID()
        XCTAssertNil(WorkoutEntryPreference.reps(in: workout, performerID: nil))
        WorkoutEntryPreference.setReps(10, in: workout, performerID: nil)
        XCTAssertEqual(WorkoutEntryPreference.reps(in: workout, performerID: nil), 10)
        XCTAssertNil(WorkoutEntryPreference.reps(in: workout, performerID: partner))
        WorkoutEntryPreference.setReps(12, in: workout, performerID: partner)
        XCTAssertEqual(WorkoutEntryPreference.reps(in: workout, performerID: nil), 10)
        XCTAssertEqual(WorkoutEntryPreference.reps(in: workout, performerID: partner), 12)
        XCTAssertNil(WorkoutEntryPreference.reps(in: WorkoutSession(title: "Next"), performerID: nil))
    }
}
#endif
