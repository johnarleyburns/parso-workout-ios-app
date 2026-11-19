#if canImport(SwiftData)
import Foundation
import Testing
import SwiftData
@testable import CadenceCore

struct TrainingEngineBridgeTests {
    @Test func bundledEndurancePolicyProvidesAppDefaults() throws {
        let defaults = try #require(
            TrainingEngineBridge.goalDefaults(policyId: "general-endurance-v1")
        )

        #expect(defaults.reps == 15...20)
        #expect(defaults.rir == 2)
        #expect(TrainingGoal.endurance.repRange == defaults.reps)
        #expect(TrainingGoal.endurance.targetRIR == defaults.rir)
    }

    @Test func enduranceFallbackMatchesPolicyWhenEngineIsUnavailable() {
        let unavailable = TrainingEngineBridge.goalDefaults(
            policyId: "general-endurance-v1",
            useSharedEngine: false
        )

        #expect(unavailable == nil)
        #expect((unavailable?.reps ?? 15...20) == 15...20)
        #expect((unavailable?.rir ?? 2) == 2)
    }

    @Test func unknownGoalPolicyDoesNotProduceDefaults() {
        #expect(TrainingEngineBridge.goalDefaults(policyId: "unknown-policy") == nil)
    }

    @Test func requestBuildersTranslateAppStateDeterministically() {
        let schedule = CoachSchedulePreferences(
            restPreference: .fixed(days: [.sunday, .wednesday]))
        let profile = TrainingEngineBridge.trainingProfile(
            experience: .intermediate,
            schedule: schedule,
            availableEquipment: [.barbell, .bodyweight],
            subjectId: "subject-1")

        #expect(profile.subjectId == "subject-1")
        #expect(profile.experience == "intermediate")
        #expect(profile.equipment == ["barbell", "body only", "e-z curl bar"])
        #expect(profile.availability?.sessionsPerCycle?.target == 1,
                       "One launchable session per cycle; no weekly day quota is sent")

        let target = TrainingEngineBridge.volumeTarget(
            trackedGroups: [.chest, .lats],
            experience: .intermediate)
        #expect(target.periodDays == 7)
        #expect(target.muscles[MuscleGroup.chest.rawValue]?.min == 8)
        #expect(target.muscles[MuscleGroup.chest.rawValue]?.target == 16)
        #expect(target.muscles[MuscleGroup.lats.rawValue]?.max == 22)

        let intent = TrainingEngineBridge.workoutIntent(
            goal: .hypertrophy,
            environment: "commercial_gym",
            schedule: schedule,
            style: .bodyweight)
        #expect(intent.goal == "hypertrophy")
        #expect(intent.environment == "commercial_gym")
        #expect(intent.requestedGoalPolicy == nil)
        #expect(intent.schedule?.excludedWeekdays == ["sunday", "wednesday"])
        #expect(!(intent.preferences?.preferredExerciseIds.isEmpty ?? true))
    }

    @Test func fixedProfileAndTargetProduceStablePlanAndRoundTrip() throws {
        let profile = TrainingEngineBridge.trainingProfile(
            experience: .intermediate,
            schedule: CoachSchedulePreferences(),
            availableEquipment: Equipment.allCases,
            subjectId: "subject-1")
        let target = TrainingEngineBridge.volumeTarget(
            trackedGroups: [.chest],
            experience: .intermediate)
        let asOf = Date(timeIntervalSince1970: 1_750_000_000.125)

        let firstResult = try #require(
            TrainingEngineBridge.run(.generatePlan, asOf: asOf, profile: profile, target: target))
        let secondResult = try #require(
            TrainingEngineBridge.run(.generatePlan, asOf: asOf, profile: profile, target: target))
        let firstPlan = try #require(firstResult.plan)
        let secondPlan = try #require(secondResult.plan)

        #expect(firstResult.status == "generated")
        #expect(firstPlan == secondPlan)

        let data = try #require(TrainingEngineBridge.serialize(firstPlan))
        #expect(TrainingEngineBridge.deserializePlan(data) == firstPlan)

        let mapped = TrainingEngineBridge.recommendedExercises(from: firstPlan.sessions[0])
        #expect(!mapped.isEmpty)
        #expect(mapped.allSatisfy { $0.sets != nil && $0.repsLow != nil })

        let weekly = TrainingEngineBridge.weeklyPlan(
            from: firstPlan,
            startingOn: Date(timeIntervalSince1970: 1_750_000_000))
        #expect(weekly.days.count == Set(firstPlan.sessions.map(\.dayOffset)).count)
        #expect(weekly.days.first?.sessions.first?.exercises == mapped)
    }

    @Test func overConstrainedIntentProducesUnsatisfiableOutcome() throws {
        let schedule = CoachSchedulePreferences()
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
            Issue.record("Expected an unsatisfiable engine outcome")
            return
        }
        #expect(issues.isEmpty || issues.contains { $0.code == "NO_ELIGIBLE_EXERCISE" })
    }

    @Test func trainingHistoryMapsFinalizedOwnerWorkoutsAndPlanReference() throws {
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
            schedule: CoachSchedulePreferences(),
            availableEquipment: Equipment.allCases)
        let target = TrainingEngineBridge.volumeTarget(
            trackedGroups: [.chest], experience: .intermediate)
        let plan = try #require(
            TrainingEngineBridge.run(.generatePlan, asOf: start, profile: profile, target: target)?.plan)
        session.enginePlanId = plan.planId
        session.engineRevisionId = plan.revisionId
        session.enginePlanJSON = TrainingEngineBridge.serialize(plan)

        let history = TrainingEngineBridge.trainingHistory(
            from: [session], subjectId: "history-subject")
        let workout = try #require(history.workouts.first)
        let observation = try #require(workout.exercises.first)
        let set = try #require(observation.sets.first)

        #expect(history.subjectId == "history-subject")
        #expect(workout.schemaVersion == "0.3.0")
        #expect(workout.planReference?.planId == plan.planId)
        #expect(workout.planReference?.revisionId == plan.revisionId)
        #expect(observation.exerciseName == "History Bench")
        #expect(observation.exerciseId == nil, "Ad-hoc app exercises remain name-addressable")
        #expect(set.reps == 8)
        #expect(set.load?.value == 80)
        #expect(set.rpe == 8)
        #expect(set.rir == 2)
        #expect(set.completed)
    }

    @Test func trainingHistoryRecoversLegacyRecordedWorkoutsWithoutEndMarker() throws {
        let context = ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        let session = try WorkoutRepository.createSession(
            title: "Legacy history", date: start, in: context)
        let exercise = try WorkoutRepository.findOrCreateExercise(
            named: "Legacy Bench", primaryMuscles: [MuscleGroup.chest.rawValue], in: context)
        _ = try WorkoutRepository.addSet(
            to: session, exercise: exercise, weightKg: 60, reps: 10,
            completedAt: start.addingTimeInterval(60), in: context)

        #expect(session.endedAt == nil)
        #expect(!session.isLogged)
        #expect(session.countsAsStrengthHistory)
        #expect(session.completedOwnerWorkingSetCount == 1)

        let history = TrainingEngineBridge.trainingHistory(
            from: [session], subjectId: "legacy-history")
        #expect(history.workouts.count == 1)
        #expect(history.workouts.first?.exercises.first?.sets.first?.reps == 10)
    }

    @Test func observationSnapshotUsesDBPlusPlusEffectiveSets() throws {
        let context = ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let session = try WorkoutRepository.createSession(date: now.addingTimeInterval(-600), in: context)
        let staleSession = try WorkoutRepository.createSession(
            date: now.addingTimeInterval(-8 * 86_400), in: context)
        let record = try #require(
            TrainingEngineBridge.exerciseRecords.first { $0.volumeEligible && !$0.direct.isEmpty })
        let group = try #require(MuscleGroup.canonical(record.direct[0]))
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

        let observation = try #require(TrainingEngineBridge.observationSnapshot(
            from: [session, staleSession], trackedGroups: [group], experience: .intermediate,
            subjectId: "observation-subject", asOf: now))

        #expect(observation.stateVersion == "0.1.0")
        #expect(observation.effectiveSetsByMuscle[record.direct[0]] == 1)
        #expect(observation.effectiveSetsByGroup[group] == 1)
    }

    @Test func adaptiveCoachSessionUsesEnginePlanBehindCoachSession() throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let schedule = CoachSchedulePreferences(
            trackedMuscleGroups: [.chest])
        let profile = TrainingEngineBridge.trainingProfile(
            experience: .intermediate,
            schedule: schedule,
            availableEquipment: Equipment.allCases,
            subjectId: "coach-subject")
        let target = TrainingEngineBridge.volumeTarget(
            trackedGroups: [.chest], experience: .intermediate)
        let plan = try #require(
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

        let session = try #require(TrainingEngineBridge.adaptiveCoachSession(
            from: [appSession], schedule: schedule, goal: .hypertrophy,
            experience: .intermediate, subjectId: "coach-subject", asOf: now))

        #expect(session.kind == .strength)
        #expect(session.trainingLoadTags.contains("engine"))
        #expect(!session.citationIds.isEmpty)
        #expect(session.citationIds.contains { $0.hasPrefix("exdb.") })
        #expect(session.citationIds.allSatisfy {
            CitationRegistry.citation(forId: $0) != nil
        })
        #expect(!session.citationIds.contains { $0.hasPrefix("pattern:") })
        #expect(!(session.exercises?.isEmpty ?? true))
        #expect(session.id.hasPrefix("engine."))
    }
}
#endif
