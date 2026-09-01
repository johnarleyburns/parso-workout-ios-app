import XCTest
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
}
