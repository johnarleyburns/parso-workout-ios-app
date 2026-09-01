import XCTest
import SwiftData
@testable import CadenceCore

final class TrainingEngineBridgeTests: XCTestCase {
    func testBundledEndurancePolicyProvidesAppDefaults() throws {
        let defaults = try XCTUnwrap(
            TrainingEngineBridge.goalDefaults(policyId: "general-endurance-v1")
        )

        XCTAssertEqual(defaults.reps, 15...20)
        XCTAssertEqual(defaults.rir, 2)
        XCTAssertEqual(TrainingGoal.endurance.repRange, defaults.reps)
        XCTAssertEqual(TrainingGoal.endurance.targetRIR, defaults.rir)
    }

    func testEnduranceFallbackMatchesPolicyWhenEngineIsUnavailable() {
        let unavailable = TrainingEngineBridge.goalDefaults(
            policyId: "general-endurance-v1",
            useSharedEngine: false
        )

        XCTAssertNil(unavailable)
        XCTAssertEqual(unavailable?.reps ?? 15...20, 15...20)
        XCTAssertEqual(unavailable?.rir ?? 2, 2)
    }

    func testUnknownGoalPolicyDoesNotProduceDefaults() {
        XCTAssertNil(TrainingEngineBridge.goalDefaults(policyId: "unknown-policy"))
    }

    func testRequestBuildersTranslateAppStateDeterministically() {
        let schedule = CoachSchedulePreferences(
            strengthDaysPerWeek: 3,
            restPreference: .fixed(days: [.sunday, .wednesday]))
        let profile = TrainingEngineBridge.trainingProfile(
            experience: .intermediate,
            schedule: schedule,
            availableEquipment: [.barbell, .bodyweight],
            subjectId: "subject-1")

        XCTAssertEqual(profile.subjectId, "subject-1")
        XCTAssertEqual(profile.experience, "intermediate")
        XCTAssertEqual(profile.equipment, ["barbell", "body only", "e-z curl bar"])
        XCTAssertEqual(profile.availability?.sessionsPerCycle?.target, 3)

        let target = TrainingEngineBridge.volumeTarget(
            trackedGroups: [.chest, .lats],
            experience: .intermediate)
        XCTAssertEqual(target.periodDays, 7)
        XCTAssertEqual(target.muscles[MuscleGroup.chest.rawValue]?.min, 8)
        XCTAssertEqual(target.muscles[MuscleGroup.chest.rawValue]?.target, 16)
        XCTAssertEqual(target.muscles[MuscleGroup.lats.rawValue]?.max, 22)

        let intent = TrainingEngineBridge.workoutIntent(
            goal: .hypertrophy,
            environment: "commercial_gym",
            schedule: schedule,
            style: .bodyweight)
        XCTAssertEqual(intent.goal, "hypertrophy")
        XCTAssertEqual(intent.environment, "commercial_gym")
        XCTAssertEqual(intent.requestedGoalPolicy, nil)
        XCTAssertEqual(intent.schedule?.excludedWeekdays, ["sunday", "wednesday"])
        XCTAssertFalse(intent.preferences?.preferredExerciseIds.isEmpty ?? true)
    }

    func testFixedProfileAndTargetProduceStablePlanAndRoundTrip() throws {
        let profile = TrainingEngineBridge.trainingProfile(
            experience: .intermediate,
            schedule: CoachSchedulePreferences(strengthDaysPerWeek: 2),
            availableEquipment: Equipment.allCases,
            subjectId: "subject-1")
        let target = TrainingEngineBridge.volumeTarget(
            trackedGroups: [.chest],
            experience: .intermediate)
        let asOf = Date(timeIntervalSince1970: 1_750_000_000.125)

        let firstResult = try XCTUnwrap(
            TrainingEngineBridge.run(.generatePlan, asOf: asOf, profile: profile, target: target))
        let secondResult = try XCTUnwrap(
            TrainingEngineBridge.run(.generatePlan, asOf: asOf, profile: profile, target: target))
        let firstPlan = try XCTUnwrap(firstResult.plan)
        let secondPlan = try XCTUnwrap(secondResult.plan)

        XCTAssertEqual(firstResult.status, "generated")
        XCTAssertEqual(firstPlan, secondPlan)

        let data = try XCTUnwrap(TrainingEngineBridge.serialize(firstPlan))
        XCTAssertEqual(TrainingEngineBridge.deserializePlan(data), firstPlan)

        let mapped = TrainingEngineBridge.recommendedExercises(from: firstPlan.sessions[0])
        XCTAssertFalse(mapped.isEmpty)
        XCTAssertTrue(mapped.allSatisfy { $0.sets != nil && $0.repsLow != nil })

        let weekly = TrainingEngineBridge.weeklyPlan(
            from: firstPlan,
            startingOn: Date(timeIntervalSince1970: 1_750_000_000))
        XCTAssertEqual(weekly.days.count, Set(firstPlan.sessions.map(\.dayOffset)).count)
        XCTAssertEqual(weekly.days.first?.sessions.first?.exercises, mapped)
    }

    func testOverConstrainedIntentProducesUnsatisfiableOutcome() throws {
        let schedule = CoachSchedulePreferences(strengthDaysPerWeek: 2)
        let intent = TrainingEngineBridge.workoutIntent(
            goal: .strength,
            environment: "commercial_gym",
            schedule: schedule,
            constraints: .init(requiredExerciseIds: ["not-a-real-exercise"]))
        let profile = TrainingEngineBridge.trainingProfile(
            experience: .beginner,
            schedule: schedule,
            availableEquipment: Equipment.allCases)
        let target = TrainingEngineBridge.volumeTarget(
            trackedGroups: [.chest],
            experience: .beginner)

        let result = TrainingEngineBridge.run(
            .generateFromIntent,
            asOf: Date(timeIntervalSince1970: 1_750_000_000),
            intent: intent,
            profile: profile,
            target: target)
        let outcome = TrainingEngineBridge.outcome(for: result, payload: result?.plan)

        guard case .unsatisfiable(let issues) = outcome else {
            return XCTFail("Expected an unsatisfiable engine outcome")
        }
        XCTAssertTrue(issues.isEmpty || issues.contains { $0.code == "NO_ELIGIBLE_EXERCISE" })
    }

    func testTrainingHistoryMapsFinalizedOwnerWorkoutsAndPlanReference() throws {
        let context = ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        let session = try WorkoutRepository.createSession(date: start, in: context)
        let exercise = try WorkoutRepository.findOrCreateExercise(
            named: "History Bench", primaryMuscles: [MuscleGroup.chest.rawValue], in: context)
        _ = try WorkoutRepository.addSet(to: session, exercise: exercise,
                                         weightKg: 80, reps: 8, rpe: 8,
                                         completedAt: start.addingTimeInterval(60), in: context)
        session.endedAt = start.addingTimeInterval(600)

        let profile = TrainingEngineBridge.trainingProfile(
            experience: .intermediate,
            schedule: CoachSchedulePreferences(strengthDaysPerWeek: 2),
            availableEquipment: Equipment.allCases)
        let target = TrainingEngineBridge.volumeTarget(
            trackedGroups: [.chest], experience: .intermediate)
        let plan = try XCTUnwrap(
            TrainingEngineBridge.run(.generatePlan, asOf: start, profile: profile, target: target)?.plan)
        session.enginePlanId = plan.planId
        session.engineRevisionId = plan.revisionId
        session.enginePlanJSON = TrainingEngineBridge.serialize(plan)

        let history = TrainingEngineBridge.trainingHistory(
            from: [session], subjectId: "history-subject")
        let workout = try XCTUnwrap(history.workouts.first)
        let observation = try XCTUnwrap(workout.exercises.first)
        let set = try XCTUnwrap(observation.sets.first)

        XCTAssertEqual(history.subjectId, "history-subject")
        XCTAssertEqual(workout.schemaVersion, "0.3.0")
        XCTAssertEqual(workout.planReference?.planId, plan.planId)
        XCTAssertEqual(workout.planReference?.revisionId, plan.revisionId)
        XCTAssertEqual(observation.exerciseName, "History Bench")
        XCTAssertNil(observation.exerciseId, "Ad-hoc app exercises remain name-addressable")
        XCTAssertEqual(set.reps, 8)
        XCTAssertEqual(set.load?.value, 80)
        XCTAssertEqual(set.rpe, 8)
        XCTAssertEqual(set.rir, 2)
        XCTAssertTrue(set.completed)
    }

    func testObservationSnapshotUsesDBPlusPlusEffectiveSets() throws {
        let context = ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let session = try WorkoutRepository.createSession(date: now.addingTimeInterval(-600), in: context)
        let staleSession = try WorkoutRepository.createSession(
            date: now.addingTimeInterval(-8 * 86_400), in: context)
        let record = try XCTUnwrap(
            TrainingEngineBridge.exerciseRecords.first { $0.volumeEligible && !$0.direct.isEmpty })
        let group = try XCTUnwrap(MuscleGroup.canonical(record.direct[0]))
        let exercise = Exercise(
            name: record.name,
            category: .legs,
            primaryMuscles: record.primaryMuscles,
            secondaryMuscles: record.secondaryMuscles,
            directMuscles: record.direct.compactMap(MuscleGroup.canonical),
            indirectMuscles: record.indirect.compactMap(MuscleGroup.canonical),
            stabilizerMuscles: record.stabilizers.compactMap(MuscleGroup.canonical),
            volumeEligible: true,
            sourceExerciseID: record.exerciseId)
        context.insert(exercise)
        _ = try WorkoutRepository.addSet(to: session, exercise: exercise,
                                         weightKg: 60, reps: 8,
                                         completedAt: session.date, in: context)
        session.endedAt = session.date.addingTimeInterval(300)
        _ = try WorkoutRepository.addSet(to: staleSession, exercise: exercise,
                                         weightKg: 60, reps: 8,
                                         completedAt: staleSession.date, in: context)
        staleSession.endedAt = staleSession.date.addingTimeInterval(300)

        let observation = try XCTUnwrap(TrainingEngineBridge.observationSnapshot(
            from: [session, staleSession], trackedGroups: [group], experience: .intermediate,
            subjectId: "observation-subject", asOf: now))

        XCTAssertEqual(observation.stateVersion, "0.1.0")
        XCTAssertEqual(observation.effectiveSetsByMuscle[record.direct[0]], 1)
        XCTAssertEqual(observation.effectiveSetsByGroup[group], 1)
    }

    func testAdaptiveCoachSessionUsesEnginePlanBehindCoachSession() throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let schedule = CoachSchedulePreferences(
            strengthDaysPerWeek: 2, trackedMuscleGroups: [.chest])
        let profile = TrainingEngineBridge.trainingProfile(
            experience: .intermediate,
            schedule: schedule,
            availableEquipment: Equipment.allCases,
            subjectId: "coach-subject")
        let target = TrainingEngineBridge.volumeTarget(
            trackedGroups: [.chest], experience: .intermediate)
        let plan = try XCTUnwrap(
            TrainingEngineBridge.run(
                .generatePlan,
                asOf: now,
                profile: profile,
                target: target)?.plan)
        let context = ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
        let appSession = try WorkoutRepository.createSession(
            date: now.addingTimeInterval(-86_400), in: context)
        appSession.endedAt = now.addingTimeInterval(-86_300)
        appSession.enginePlanId = plan.planId
        appSession.engineRevisionId = plan.revisionId
        appSession.enginePlanJSON = TrainingEngineBridge.serialize(plan)

        let session = try XCTUnwrap(TrainingEngineBridge.adaptiveCoachSession(
            from: [appSession], schedule: schedule, goal: .hypertrophy,
            experience: .intermediate, subjectId: "coach-subject", asOf: now))

        XCTAssertEqual(session.kind, .strength)
        XCTAssertTrue(session.trainingLoadTags.contains("engine"))
        XCTAssertFalse(session.citationIds.isEmpty)
        XCTAssertFalse(session.exercises?.isEmpty ?? true)
        XCTAssertTrue(session.id.hasPrefix("engine."))
    }
}
