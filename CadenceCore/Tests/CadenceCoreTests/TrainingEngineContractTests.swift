#if canImport(SwiftData)
import Foundation
import Testing
import SwiftData
@testable import CadenceCore

struct TrainingEngineContractTests {
    private let asOf = Date(timeIntervalSince1970: 1_750_000_000.125)

    @Test func fixedEngineLoopIsDeterministicAndEligibilityGated() throws {
        let schedule = CoachSchedulePreferences(
            trackedMuscleGroups: [.chest])
        let profile = TrainingEngineBridge.trainingProfile(
            experience: .intermediate,
            schedule: schedule,
            availableEquipment: Equipment.allCases,
            subjectId: "contract-subject",
            exercisesPerSession: 4)
        let target = TrainingEngineBridge.volumeTarget(
            trackedGroups: [.chest], experience: .intermediate)

        let firstGeneration = try #require(
            TrainingEngineBridge.run(
                .generatePlan, asOf: asOf, profile: profile, target: target))
        let secondGeneration = try #require(
            TrainingEngineBridge.run(
                .generatePlan, asOf: asOf, profile: profile, target: target))
        let plan = try #require(firstGeneration.plan)

        #expect(firstGeneration.status == "generated")
        #expect(firstGeneration.requestId != secondGeneration.requestId)
        #expect(firstGeneration.plan == secondGeneration.plan)
        #expect(firstGeneration.evaluation == secondGeneration.evaluation)

        let originalEvaluation = try #require(
            TrainingEngineBridge.run(
                .evaluatePlan, asOf: asOf, profile: profile, target: target,
                plan: plan)?.evaluation)

        let context = ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
        let workout = try WorkoutRepository.createSession(
            title: "Engine contract workout",
            date: asOf.addingTimeInterval(-3 * 86_400),
            in: context)
        let prescription = try #require(
            plan.sessions
                .flatMap(\.exercises)
                .first { $0.exerciseId != nil })
        let record = try #require(
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
        #expect(history.plans == [plan])
        #expect(history.workouts.count == 1)

        let firstStateResult = try #require(
            TrainingEngineBridge.run(
                .deriveState, asOf: asOf, target: target, history: history))
        let secondStateResult = try #require(
            TrainingEngineBridge.run(
                .deriveState, asOf: asOf, target: target, history: history))
        let state = try #require(firstStateResult.trainingState)
        #expect(firstStateResult.status == "state_derived")
        #expect(firstStateResult.requestId != secondStateResult.requestId)
        #expect(firstStateResult.trainingState == secondStateResult.trainingState)

        let firstAdaptation = try #require(
            TrainingEngineBridge.run(
                .adaptPlan,
                asOf: asOf,
                profile: profile,
                target: target,
                history: history,
                trainingState: state,
                currentPlan: plan))
        let secondAdaptation = try #require(
            TrainingEngineBridge.run(
                .adaptPlan,
                asOf: asOf,
                profile: profile,
                target: target,
                history: history,
                trainingState: state,
                currentPlan: plan))
        #expect(firstAdaptation.requestId != secondAdaptation.requestId)
        #expect(firstAdaptation.adaptation == secondAdaptation.adaptation)
        let adaptedPlan = try #require(
            firstAdaptation.adaptation?.proposedPlan ?? firstAdaptation.adaptation?.currentPlan ?? plan)

        let hydratedPlan = try #require(
            workout.enginePlanJSON.flatMap(TrainingEngineBridge.deserializePlan))
        let hydratedEvaluation = try #require(
            TrainingEngineBridge.run(
                .evaluatePlan, asOf: asOf, profile: profile, target: target,
                plan: hydratedPlan)?.evaluation)
        #expect(hydratedPlan == plan)
        #expect(hydratedEvaluation == originalEvaluation)

        let candidateExercises = TrainingEngineBridge.recommendedExercises(
            from: adaptedPlan.sessions.sorted { $0.planSessionId < $1.planSessionId }[0])
        #expect(!candidateExercises.isEmpty)
        let candidate = CoachSession(
            id: "engine.contract",
            kind: .strength,
            title: "Engine contract session",
            exercises: candidateExercises,
            launchPayload: .strengthPlan("engine.contract"))
        let facts = CoachFacts.make(
            from: [], goal: .hypertrophy, experience: .intermediate, now: asOf)

        guard case .eligible = SessionEligibilityPolicy.evaluate(candidate, facts: facts) else {
            Issue.record("The engine proposal should pass the app eligibility gate with no conflicting history")
            return
        }
    }

    @Test func dBPlusPlusImportBoundaryHasOneOwner() throws {
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

        // The engine bridge, plus the single explicit Garmin FIT codec adapter.
        #expect(
            importOwners.map(\.lastPathComponent).sorted() ==
            ["GarminFITBridge.swift", "TrainingEngineBridge.swift"])
    }
}
#endif
