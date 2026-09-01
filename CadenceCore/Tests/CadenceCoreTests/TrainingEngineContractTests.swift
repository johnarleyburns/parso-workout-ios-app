import XCTest
import SwiftData
@testable import CadenceCore

final class TrainingEngineContractTests: XCTestCase {
    private let asOf = Date(timeIntervalSince1970: 1_750_000_000.125)

    func testFixedEngineLoopIsDeterministicAndEligibilityGated() throws {
        let schedule = CoachSchedulePreferences(
            strengthDaysPerWeek: 1,
            trackedMuscleGroups: [.chest])
        let profile = TrainingEngineBridge.trainingProfile(
            experience: .intermediate,
            schedule: schedule,
            availableEquipment: Equipment.allCases,
            subjectId: "contract-subject",
            exercisesPerSession: 4)
        let target = TrainingEngineBridge.volumeTarget(
            trackedGroups: [.chest], experience: .intermediate)

        let firstGeneration = try XCTUnwrap(
            TrainingEngineBridge.run(
                .generatePlan, asOf: asOf, profile: profile, target: target))
        let secondGeneration = try XCTUnwrap(
            TrainingEngineBridge.run(
                .generatePlan, asOf: asOf, profile: profile, target: target))
        let plan = try XCTUnwrap(firstGeneration.plan)

        XCTAssertEqual(firstGeneration.status, "generated")
        XCTAssertNotEqual(firstGeneration.requestId, secondGeneration.requestId)
        XCTAssertEqual(firstGeneration.plan, secondGeneration.plan)
        XCTAssertEqual(firstGeneration.evaluation, secondGeneration.evaluation)

        let originalEvaluation = try XCTUnwrap(
            TrainingEngineBridge.run(
                .evaluatePlan, asOf: asOf, profile: profile, target: target,
                plan: plan)?.evaluation)

        let context = ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
        let workout = try WorkoutRepository.createSession(
            title: "Engine contract workout",
            date: asOf.addingTimeInterval(-3 * 86_400),
            in: context)
        let prescription = try XCTUnwrap(
            plan.sessions
                .flatMap(\.exercises)
                .first { $0.exerciseId != nil })
        let record = try XCTUnwrap(
            prescription.exerciseId.flatMap { id in
                TrainingEngineBridge.exerciseRecords.first { $0.exerciseId == id }
            })
        let exercise = Exercise(
            name: record.name,
            category: ExerciseCategory(rawValue: record.category),
            primaryMuscles: record.primaryMuscles,
            secondaryMuscles: record.secondaryMuscles,
            directMuscles: record.direct.compactMap(MuscleGroup.canonical),
            indirectMuscles: record.indirect.compactMap(MuscleGroup.canonical),
            stabilizerMuscles: record.stabilizers.compactMap(MuscleGroup.canonical),
            volumeEligible: record.volumeEligible,
            sourceExerciseID: record.exerciseId)
        context.insert(exercise)
        _ = try WorkoutRepository.addSet(
            to: workout,
            exercise: exercise,
            weightKg: 60,
            reps: 8,
            rpe: 7,
            completedAt: workout.date,
            in: context)
        workout.endedAt = workout.date.addingTimeInterval(300)
        workout.enginePlanId = plan.planId
        workout.engineRevisionId = plan.revisionId
        workout.enginePlanJSON = TrainingEngineBridge.serialize(plan)
        try context.save()

        let history = TrainingEngineBridge.trainingHistory(
            from: [workout], subjectId: "contract-subject")
        XCTAssertEqual(history.plans, [plan])
        XCTAssertEqual(history.workouts.count, 1)

        let firstStateResult = try XCTUnwrap(
            TrainingEngineBridge.run(
                .deriveState, asOf: asOf, target: target, history: history))
        let secondStateResult = try XCTUnwrap(
            TrainingEngineBridge.run(
                .deriveState, asOf: asOf, target: target, history: history))
        let state = try XCTUnwrap(firstStateResult.trainingState)
        XCTAssertEqual(firstStateResult.status, "state_derived")
        XCTAssertNotEqual(firstStateResult.requestId, secondStateResult.requestId)
        XCTAssertEqual(firstStateResult.trainingState, secondStateResult.trainingState)

        let firstAdaptation = try XCTUnwrap(
            TrainingEngineBridge.run(
                .adaptPlan,
                asOf: asOf,
                profile: profile,
                target: target,
                history: history,
                trainingState: state,
                currentPlan: plan))
        let secondAdaptation = try XCTUnwrap(
            TrainingEngineBridge.run(
                .adaptPlan,
                asOf: asOf,
                profile: profile,
                target: target,
                history: history,
                trainingState: state,
                currentPlan: plan))
        XCTAssertNotEqual(firstAdaptation.requestId, secondAdaptation.requestId)
        XCTAssertEqual(firstAdaptation.adaptation, secondAdaptation.adaptation)
        let adaptedPlan = try XCTUnwrap(
            firstAdaptation.adaptation?.proposedPlan ?? firstAdaptation.adaptation?.currentPlan ?? plan)

        let hydratedPlan = try XCTUnwrap(
            workout.enginePlanJSON.flatMap(TrainingEngineBridge.deserializePlan))
        let hydratedEvaluation = try XCTUnwrap(
            TrainingEngineBridge.run(
                .evaluatePlan, asOf: asOf, profile: profile, target: target,
                plan: hydratedPlan)?.evaluation)
        XCTAssertEqual(hydratedPlan, plan)
        XCTAssertEqual(hydratedEvaluation, originalEvaluation)

        let candidateExercises = TrainingEngineBridge.recommendedExercises(
            from: adaptedPlan.sessions.sorted { $0.planSessionId < $1.planSessionId }[0])
        XCTAssertFalse(candidateExercises.isEmpty)
        let candidate = CoachSession(
            id: "engine.contract",
            kind: .strength,
            title: "Engine contract session",
            exercises: candidateExercises,
            launchPayload: .strengthPlan("engine.contract"))
        let facts = CoachFacts.make(
            from: [], goal: .hypertrophy, experience: .intermediate, now: asOf)

        guard case .eligible = SessionEligibilityPolicy.evaluate(candidate, facts: facts) else {
            return XCTFail("The engine proposal should pass the app eligibility gate with no conflicting history")
        }
    }

    func testDBPlusPlusImportBoundaryHasOneOwner() throws {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // CadenceCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // CadenceCore
            .appendingPathComponent("Sources")
        let enumerator = FileManager.default.enumerator(
            at: sourceRoot,
            includingPropertiesForKeys: nil)
        let swiftFiles = (enumerator?.compactMap { $0 as? URL } ?? [])
            .filter { $0.pathExtension == "swift" }
        let importOwners = swiftFiles.filter { url in
            guard let source = try? String(contentsOf: url, encoding: .utf8) else { return false }
            return source.contains("import FreeExerciseDBPlusPlus")
        }

        XCTAssertEqual(
            importOwners.map(\.lastPathComponent),
            ["TrainingEngineBridge.swift"])
    }
}
