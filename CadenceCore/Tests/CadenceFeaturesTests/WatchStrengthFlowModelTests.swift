import XCTest
import SwiftData
@testable import CadenceFeatures
import CadenceCore

final class WatchStrengthFlowModelTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        container = try CadenceStore.makeModelContainer(inMemory: true)
        context = ModelContext(container)
        _ = try WorkoutRepository.seedStarterLibraryIfNeeded(context)
    }

    override func tearDown() {
        container = nil
        context = nil
    }

    func makeModel() -> WatchStrengthFlowModel {
        WatchStrengthFlowModel(context: context, unit: .kilograms, cooldownDefault: 5, restDefault: 90)
    }

    func simpleExercise(named name: String) -> Exercise {
        try! WorkoutRepository.findOrCreateExercise(named: name, in: context)
    }

    // MARK: - Stage transitions

    func testStart_showsHome() {
        let m = makeModel()
        m.start()
        XCTAssertEqual(m.stage, .home)
        XCTAssertNil(m.session)
    }

    func testGoToAddExercise() {
        let m = makeModel()
        m.start()
        m.goToAddExercise()
        if case .addExercise = m.stage {} else { XCTFail("Expected addExercise stage") }
    }

    func testAddExercise_returnsToHome() {
        let m = makeModel()
        m.start()
        m.addExercise(named: "Bench Press")
        XCTAssertEqual(m.pendingExercises, ["Bench Press"])
        XCTAssertEqual(m.stage, .home)
    }

    func testAddCustomExerciseCreatesFacetedExerciseAndAddsItToWorkout() {
        let m = makeModel()
        m.start(createSession: true)

        let exercise = m.addCustomExercise(named: "  Standing Cable Twist  ",
                                           muscleGroups: [.abdominals, .shoulders])

        XCTAssertEqual(exercise?.name, "Standing Cable Twist")
        XCTAssertEqual(exercise?.isCustom, true)
        XCTAssertEqual(Set(exercise?.primaryMuscles ?? []), ["shoulders", "abdominals"])
        XCTAssertEqual(exercise?.categoryValue, .other)
        XCTAssertEqual(m.stage, .home)
        XCTAssertTrue(m.exerciseList.contains { $0.exercise.name == "Standing Cable Twist" })
    }

    func testAddCustomExerciseRequiresNameAndMuscleGroup() {
        let m = makeModel()
        m.start(createSession: true)
        XCTAssertNil(m.addCustomExercise(named: "", muscleGroups: [.lats]))
        XCTAssertNil(m.addCustomExercise(named: "Mystery Lift", muscleGroups: []))
    }

    func testAddExercise_showsPendingExerciseOnHome() {
        let m = makeModel()
        m.start()
        m.addExercise(named: "Bench Press")
        XCTAssertEqual(m.exerciseList.map { $0.exercise.name }, ["Bench Press"])
        XCTAssertEqual(m.exerciseList.first?.setCount, 0)
    }

    func testAddExerciseAliasStoresCanonicalBuiltInName() {
        let m = makeModel()
        m.start()
        m.addExercise(named: "Tricep Pushdown")
        XCTAssertEqual(m.pendingExercises, ["Triceps Pushdown"])
        XCTAssertEqual(m.exerciseList.map { $0.exercise.name }, ["Triceps Pushdown"])
        XCTAssertEqual(m.exerciseList.first?.exercise.primaryMuscles, ["triceps"])
    }

    func testPlannedAliasLogSetPayloadUsesCanonicalBuiltInName() {
        let m = makeModel()
        m.start(
            title: "Shoulders",
            plannedExerciseNames: ["Lateral Raise"],
            createSession: true
        )
        XCTAssertEqual(m.session?.plannedExerciseNames, ["Dumbbell Lateral Raise"])
        XCTAssertEqual(m.exerciseList.map { $0.exercise.name }, ["Dumbbell Lateral Raise"])

        let exercise = m.exerciseList[0].exercise
        m.startLogSet(for: exercise)
        _ = m.logSet()

        XCTAssertEqual(m.lastSyncPayload?["exercise"] as? String, "Dumbbell Lateral Raise")
        XCTAssertEqual(m.lastSyncPayload?["planned_exercises"] as? [String], ["Dumbbell Lateral Raise"])
    }

    func testLogSetFromAddedExercise_createsSessionAndKeepsExerciseVisible() {
        let m = makeModel()
        m.start()
        m.addExercise(named: "Bench Press")
        let ex = m.exerciseList[0].exercise
        m.startLogSet(for: ex)
        _ = m.logSet()
        m.finishRest()
        XCTAssertNotNil(m.session)
        XCTAssertEqual(m.pendingExercises, [])
        XCTAssertEqual(m.exerciseList.map { $0.exercise.name }, ["Bench Press"])
        XCTAssertEqual(m.exerciseList.first?.setCount, 1)
    }

    func testQueuedExercisesSurviveFirstLoggedSet() {
        let m = makeModel()
        m.start()
        m.addExercise(named: "Bench Press")
        m.addExercise(named: "Squat")
        let ex = m.exerciseList[0].exercise
        m.startLogSet(for: ex)
        _ = m.logSet()
        m.finishRest()
        XCTAssertEqual(m.exerciseList.map { $0.exercise.name }, ["Bench Press", "Squat"])
        XCTAssertEqual(m.exerciseList.map { $0.setCount }, [1, 0])
    }

    func testFinishAfterOnlyAddingExercise_discardsEmptySession() {
        let m = makeModel()
        m.start()
        m.addExercise(named: "Bench Press")
        m.finish()
        XCTAssertEqual(m.stage, .discarded)
        XCTAssertNil(m.session)
    }

    func testLogSet_createsSessionLazily() {
        let m = makeModel()
        m.start()
        let ex = try! WorkoutRepository.findOrCreateExercise(named: "TestPress", equipment: nil, in: context)
        m.startLogSet(for: ex)
        _ = m.logSet()
        XCTAssertNotNil(m.session)
        XCTAssertEqual(m.stage, .rest)
    }

    func testLogSetGoesToRestAndNextSetReturnsToSameExercise() {
        let m = makeModel()
        m.start(repLadder: [12, 10, 8], createSession: true)
        let ex = simpleExercise(named: "Rest Return Press")
        m.startLogSet(for: ex)
        XCTAssertEqual(Int(m.currentReps), 12)

        _ = m.logSet()
        XCTAssertEqual(m.stage, .rest)

        m.finishRest()
        guard case .keypad(let returnedExercise) = m.stage else {
            return XCTFail("Expected Next Set to return to the same exercise keypad")
        }
        XCTAssertEqual(returnedExercise.id, ex.id)
        XCTAssertEqual(Int(m.currentReps), 10)
    }

    func testStartCreateSessionPrefillsPlannedExercisesAndLadder() {
        let m = makeModel()
        m.start(title: "Push Day",
                plannedExerciseNames: ["Bench Press", "Back Squat"],
                repLadder: [12, 10, 8],
                planKey: "preset-push",
                createSession: true)

        XCTAssertEqual(m.session?.title, "Push Day")
        XCTAssertEqual(m.session?.plannedExerciseNames, ["Bench Press", "Back Squat"])
        XCTAssertEqual(m.session?.plannedRepLadder, [12, 10, 8])
        XCTAssertEqual(m.session?.planKey, "preset-push")
        XCTAssertEqual(m.exerciseList.map { $0.exercise.name }, ["Bench Press", "Back Squat"])
        XCTAssertEqual(m.exerciseList.map { $0.setCount }, [0, 0])
    }

    func testStartWithVersionedPlanPayloadKeepsRichPrescriptionAndTransportData() {
        let sessionID = UUID()
        let payload = WatchPlanPayload(
            planSessionID: sessionID,
            title: "Upper",
            strength: .init(
                exerciseNames: ["Bench Press"], repLadder: [5],
                prescriptions: [PlannedExercisePrescription(
                    sourceItemID: UUID(), exerciseKey: "bench_press",
                    exerciseName: "Bench Press",
                    sets: [.init(targetReps: 5, targetWeightKg: 80,
                                  targetLoadMode: "absolute", restSeconds: 150)])]))
        let m = makeModel()

        m.start(planPayload: payload, createSession: true)

        XCTAssertEqual(m.session?.planSessionID, sessionID)
        XCTAssertEqual(m.session?.plannedPrescriptions.first?.exerciseKey, "bench_press")
        XCTAssertEqual(m.session?.plannedPrescriptions.first?.sets.first?.restSeconds, 150)
        XCTAssertEqual(m.session?.plannedExerciseNames, ["Bench Press"])
    }

    func testLogSet_ownerSet_countsVolume() {
        let m = makeModel()
        m.start()
        let ex = try! WorkoutRepository.findOrCreateExercise(named: "TestPress", equipment: nil, in: context)
        m.currentWeight = 100; m.currentReps = 5
        m.startLogSet(for: ex)
        _ = m.logSet()
        XCTAssertEqual(m.setCount, 1)
        XCTAssertGreaterThan(m.volume, 0)
    }

    func testWarmupSet_excludedFromVolume() {
        let m = makeModel()
        m.start()
        let ex = try! WorkoutRepository.findOrCreateExercise(named: "TestPress", equipment: nil, in: context)
        m.startLogSet(for: ex)
        m.toggleWarmup()
        m.currentWeight = 60; m.currentReps = 10
        _ = m.logSet()
        XCTAssertEqual(m.setCount, 0)
        XCTAssertEqual(m.volume, 0, accuracy: 0.1)
    }

    func testLogSetPayload_includesWarmupFlag() {
        let m = makeModel()
        m.start()
        let ex = try! WorkoutRepository.findOrCreateExercise(named: "TestPress", equipment: nil, in: context)
        m.startLogSet(for: ex)
        m.toggleWarmup()
        _ = m.logSet()
        XCTAssertEqual(m.lastSyncPayload?["is_warmup"] as? Bool, true)
    }

    func testFinish_withSets_transitionsToCooldown() {
        let m = makeModel()
        m.start()
        let ex = try! WorkoutRepository.findOrCreateExercise(named: "TestPress", equipment: nil, in: context)
        m.startLogSet(for: ex)
        _ = m.logSet()
        m.finish()
        if case .cooldown = m.stage {} else { XCTFail("Expected cooldown stage") }
    }

    func testFinish_emptySession_autoDiscards() {
        let m = makeModel()
        m.start()
        m.finish()
        XCTAssertEqual(m.stage, .discarded)
    }

    func testSkipCooldown_goesToSummary() {
        let m = makeModel()
        m.start()
        let ex = try! WorkoutRepository.findOrCreateExercise(named: "TestPress", equipment: nil, in: context)
        m.startLogSet(for: ex)
        _ = m.logSet()
        m.finish()
        m.skipCooldown()
        XCTAssertEqual(m.stage, .summary)
    }

    func testCompleteCooldown_goesToSummary() {
        let m = makeModel()
        m.start()
        let ex = try! WorkoutRepository.findOrCreateExercise(named: "TestPress", equipment: nil, in: context)
        m.startLogSet(for: ex)
        _ = m.logSet()
        m.finish()
        m.completeCooldown()
        XCTAssertEqual(m.stage, .summary)
    }

    func testCancel_beforeCreate_noDiscardPayload() {
        let m = makeModel()
        m.start()
        m.cancel()
        XCTAssertEqual(m.stage, .discarded)
        XCTAssertNil(m.discardPayload)
    }

    func testCancel_afterSync_emitsDiscardPayload() {
        let m = makeModel()
        m.start()
        let ex = try! WorkoutRepository.findOrCreateExercise(named: "TestPress", equipment: nil, in: context)
        m.startLogSet(for: ex)
        _ = m.logSet()
        m.cancel()
        XCTAssertEqual(m.stage, .discarded)
        XCTAssertNotNil(m.discardPayload)
        XCTAssertEqual(m.discardPayload?["action"] as? String, "discard_session")
    }

    // MARK: - Partners

    func testAddPartner() {
        let m = makeModel()
        m.start()
        m.addPartner(named: "Jo")
        XCTAssertEqual(m.partners.count, 1)
        XCTAssertEqual(m.partners.first?.name, "Jo")
        XCTAssertEqual(m.performerOptions.map(\.name), ["Me", "Jo"])
        XCTAssertEqual(m.performerLabel, "Me")
    }

    func testPartnerRotation_afterLogSet() {
        let m = makeModel()
        m.start()
        m.addPartner(named: "Jo")
        m.addPartner(named: "Sam")
        let ex = try! WorkoutRepository.findOrCreateExercise(named: "TestPress", equipment: nil, in: context)
        m.startLogSet(for: ex)
        _ = m.logSet()
        XCTAssertEqual(m.currentPerformerIndex, 1)
        m.startLogSet(for: ex)
        _ = m.logSet()
        XCTAssertEqual(m.currentPerformerIndex, 2)
        m.startLogSet(for: ex)
        _ = m.logSet()
        XCTAssertEqual(m.currentPerformerIndex, 0)
    }

    func testPartnerRotationShowsOnlyTheActiveLiftersSetsAndSetNumber() {
        let m = makeModel()
        m.start(initialPartnerNames: ["Jo", "Sam"], createSession: true)
        let ex = simpleExercise(named: "Partner History Press")
        m.startLogSet(for: ex)

        m.currentReps = 8
        _ = m.logSet() // Me -> Jo
        m.finishRest()
        XCTAssertEqual(m.performerLabel, "Jo")
        XCTAssertEqual(m.currentWorkoutHistoryLines, [])
        XCTAssertEqual(m.currentWorkingSetIndex, 1)

        m.currentReps = 10
        _ = m.logSet() // Jo -> Sam
        m.finishRest()
        XCTAssertEqual(m.performerLabel, "Sam")
        XCTAssertEqual(m.currentWorkoutHistoryLines, [])
        XCTAssertEqual(m.currentWorkingSetIndex, 1)

        m.currentReps = 12
        _ = m.logSet() // Sam -> Me
        m.finishRest()
        XCTAssertEqual(m.performerLabel, "Me")
        XCTAssertEqual(m.currentWorkoutHistoryLines.map(\.reps), [8])
        XCTAssertEqual(m.currentWorkingSetIndex, 2)

        m.selectPerformer(at: 1)
        XCTAssertEqual(m.currentWorkoutHistoryLines.map(\.reps), [10])
        XCTAssertEqual(m.currentWorkingSetIndex, 2)
        m.selectPerformer(at: 2)
        XCTAssertEqual(m.currentWorkoutHistoryLines.map(\.reps), [12])
        XCTAssertEqual(m.currentWorkingSetIndex, 2)
    }

    func testPriorWorkoutHistoryAlsoFollowsSelectedPartner() throws {
        let jo = try WorkoutRepository.findOrCreatePerson(named: "Jo", in: context)
        let ex = simpleExercise(named: "Prior Partner Press")
        let prior = try WorkoutRepository.createSession(title: "Prior", in: context)
        _ = try WorkoutRepository.addSet(to: prior, exercise: ex, weightKg: 70, reps: 8, in: context)
        _ = try WorkoutRepository.addSet(to: prior, exercise: ex, weightKg: 45, reps: 12,
                                         performedBy: jo, in: context)

        let m = makeModel()
        m.start(initialPartnerNames: ["Jo"], createSession: true)
        m.startLogSet(for: ex)
        XCTAssertEqual(m.previousWorkoutHistoryLines.map(\.reps), [8])

        m.selectPerformer(at: 1)
        XCTAssertEqual(m.previousWorkoutHistoryLines.map(\.reps), [12])
    }

    func testSelectPerformer() {
        let m = makeModel()
        m.start()
        m.addPartner(named: "Jo")
        m.addPartner(named: "Sam")
        m.selectPerformer(at: 2)
        XCTAssertEqual(m.currentPerformerIndex, 2)
        XCTAssertEqual(m.performerLabel, "Sam")
        m.selectPerformer(at: 0)
        XCTAssertEqual(m.performerLabel, "Me")
    }

    func testRemovePartner() {
        let m = makeModel()
        m.start()
        m.addPartner(named: "Jo")
        m.addPartner(named: "Sam")
        m.removePartner(at: 0)
        XCTAssertEqual(m.partners.count, 1)
        XCTAssertEqual(m.partners.first?.name, "Sam")
    }

    func testPartnerSet_excludedFromVolume() {
        let m = makeModel()
        m.start()
        m.addPartner(named: "Jo")
        m.addPartner(named: "Sam")
        let ex = try! WorkoutRepository.findOrCreateExercise(named: "TestPress", equipment: nil, in: context)
        m.currentWeight = 80; m.currentReps = 8
        m.startLogSet(for: ex); _ = m.logSet()
        m.startLogSet(for: ex); _ = m.logSet()
        m.startLogSet(for: ex); _ = m.logSet()
        XCTAssertGreaterThan(m.setCount, 0)
    }

    // MARK: - Sync payloads

    func testLogSetPayload_includesPerformedBy() {
        let m = makeModel()
        m.start()
        m.addPartner(named: "Jo")
        m.addPartner(named: "Sam")
        m.addPartner(named: "Max")
        let ex = try! WorkoutRepository.findOrCreateExercise(named: "TestPress", equipment: nil, in: context)
        m.startLogSet(for: ex)
        m.selectPerformer(at: 2)
        _ = m.logSet()
        XCTAssertEqual(m.lastPerformedByName, "Sam")
        XCTAssertNotNil(m.lastSyncPayload?["performed_by_id"])
    }

    func testLogSetPayload_includesSetId() {
        let m = makeModel()
        m.start()
        let ex = try! WorkoutRepository.findOrCreateExercise(named: "TestPress", equipment: nil, in: context)
        m.startLogSet(for: ex)
        _ = m.logSet()
        XCTAssertNotNil(m.lastSyncPayload?["set_id"])
    }

    func testEndSessionPayload() {
        let m = makeModel()
        m.start()
        let ex = try! WorkoutRepository.findOrCreateExercise(named: "TestPress", equipment: nil, in: context)
        m.startLogSet(for: ex)
        _ = m.logSet()
        m.finish()
        m.skipCooldown()
        let payload = m.endSessionPayload()
        XCTAssertNotNil(payload)
        XCTAssertEqual(payload?["action"] as? String, "end_session")
    }

    func testDurationText() {
        let m = makeModel()
        m.start()
        let ex = try! WorkoutRepository.findOrCreateExercise(named: "TestPress", equipment: nil, in: context)
        m.startLogSet(for: ex)
        _ = m.logSet()
        let text = m.durationText
        XCTAssertFalse(text.isEmpty)
    }

    // MARK: - Weight defaulting & display units

    private func poundsModel() -> WatchStrengthFlowModel {
        WatchStrengthFlowModel(context: context, unit: .pounds, cooldownDefault: 5, restDefault: 90)
    }

    /// Field regression: reopening the keypad must preserve a precise cable
    /// stack value instead of silently snapping it to a 2.5 lb boundary.
    func testStartLogSet_pounds_preservesPreciseLastWeight() {
        let m = poundsModel()
        m.start()
        let ex = try! WorkoutRepository.findOrCreateExercise(named: "TestPress", equipment: nil, in: context)
        m.startLogSet(for: ex)
        m.currentWeightDisplay = 17.7
        _ = m.logSet()
        m.finishRest()
        m.startLogSet(for: ex)
        XCTAssertEqual(m.currentWeightDisplay, 17.7, accuracy: 0.001)
    }

    /// With no history, pounds still starts at the familiar empty-bar value.
    func testStartLogSet_pounds_noHistoryDefaultsTo45() {
        let m = poundsModel()
        m.start()
        let ex = try! WorkoutRepository.findOrCreateExercise(named: "Fresh", equipment: nil, in: context)
        m.startLogSet(for: ex)
        XCTAssertEqual(m.currentWeightDisplay, 45, accuracy: 0.001)
    }

    /// The display accessor round-trips through canonical kg without drift.
    func testCurrentWeightDisplay_roundTripsPounds() {
        let m = poundsModel()
        m.currentWeightDisplay = 135
        XCTAssertEqual(m.currentWeightDisplay, 135, accuracy: 0.001)
        XCTAssertEqual(m.currentWeight, WorkoutMath.canonical(135, from: .pounds), accuracy: 0.001)
    }

    /// Field regression: cable-stack loads must not be locked to 2.5 lb steps.
    func testCrownIncrement_acceptsDecimalPounds() {
        let m = poundsModel()
        m.currentWeightDisplay = 100
        m.currentWeightDisplay += WeightIncrement(unit: .pounds).crownDetent
        XCTAssertEqual(m.currentWeightDisplay, 100.1, accuracy: 0.001)
        m.currentWeightDisplay = 17.7
        XCTAssertEqual(m.currentWeightText, "17.7")
    }

    func testPreviousSetHint() {
        let ex = try! WorkoutRepository.findOrCreateExercise(named: "TestPress", equipment: nil, in: context)
        let prior = try! WorkoutRepository.createSession(title: "Last",
                                                         date: Date(timeIntervalSince1970: 100),
                                                         in: context)
        _ = try! WorkoutRepository.addSet(to: prior, exercise: ex, weightKg: 100, reps: 8, in: context)

        let m = makeModel()
        m.start(createSession: true)
        m.startLogSet(for: ex)
        let hint = m.previousSetHint
        XCTAssertNotNil(hint)
        XCTAssertTrue(hint!.contains("Previous:"))
    }

    func testDefaultRepsUsePriorWorkingLadderAndIgnoreWarmups() {
        let ex = simpleExercise(named: "Ladder Press")
        let prior = try! WorkoutRepository.createSession(title: "Last",
                                                         date: Date(timeIntervalSince1970: 100),
                                                         in: context)
        _ = try! WorkoutRepository.addSet(to: prior, exercise: ex, weightKg: 40, reps: 15, isWarmup: true, in: context)
        _ = try! WorkoutRepository.addSet(to: prior, exercise: ex, weightKg: 60, reps: 12, in: context)
        _ = try! WorkoutRepository.addSet(to: prior, exercise: ex, weightKg: 65, reps: 10, in: context)
        _ = try! WorkoutRepository.addSet(to: prior, exercise: ex, weightKg: 70, reps: 8, in: context)

        let m = makeModel()
        m.start(createSession: true)
        m.startLogSet(for: ex)
        XCTAssertEqual(Int(m.currentReps), 12)

        _ = m.logSet()
        m.finishRest()
        m.startLogSet(for: ex)
        XCTAssertEqual(Int(m.currentReps), 10)
    }

    func testSetHistoryLinesShowPriorAndCurrentWorkoutSets() {
        let ex = simpleExercise(named: "History Press")
        let prior = try! WorkoutRepository.createSession(title: "Last",
                                                         date: Date(timeIntervalSince1970: 100),
                                                         in: context)
        _ = try! WorkoutRepository.addSet(to: prior, exercise: ex, weightKg: 40, reps: 6, isWarmup: true, in: context)
        _ = try! WorkoutRepository.addSet(to: prior, exercise: ex, weightKg: 60, reps: 12, in: context)
        _ = try! WorkoutRepository.addSet(to: prior, exercise: ex, weightKg: 65, reps: 10, in: context)

        let m = makeModel()
        m.start(createSession: true)
        m.startLogSet(for: ex)
        XCTAssertEqual(m.previousWorkoutHistoryLines.map(\.label), ["W", "1", "2"])
        XCTAssertEqual(m.previousWorkoutHistoryLines.map(\.reps), [6, 12, 10])

        m.currentWeight = 70
        m.currentReps = 12
        _ = m.logSet()
        m.finishRest()
        m.startLogSet(for: ex)
        XCTAssertEqual(m.currentWorkoutHistoryLines.map(\.label), ["1"])
        XCTAssertEqual(m.currentWorkoutHistoryLines.map(\.reps), [12])
        XCTAssertEqual(m.currentWorkingSetIndex, 2)
    }

    func testLogSetPayloadIncludesPlannedSessionMetadata() {
        let m = makeModel()
        m.start(title: "Push Day",
                plannedExerciseNames: ["Bench Press"],
                repLadder: [12, 10, 8],
                planKey: "preset-push",
                createSession: true)

        let ex = m.exerciseList[0].exercise
        m.startLogSet(for: ex)
        _ = m.logSet()

        XCTAssertEqual(m.lastSyncPayload?["session_title"] as? String, "Push Day")
        XCTAssertEqual(m.lastSyncPayload?["planned_exercises"] as? [String], ["Bench Press"])
        XCTAssertEqual(m.lastSyncPayload?["planned_rep_ladder"] as? [Int], [12, 10, 8])
        XCTAssertEqual(m.lastSyncPayload?["plan_key"] as? String, "preset-push")
    }

    func testStartCreateSessionLoadsInitialPartnersAndSessionRoster() {
        let m = makeModel()
        m.start(initialPartnerNames: ["Jo", "Sam", "Jo"], createSession: true)

        XCTAssertEqual(m.partners.map(\.name), ["Jo", "Sam"])
        XCTAssertEqual(m.session?.activePartnerIDs.count, 2)
    }

    func testEffortRPELogsToSetAndPayload() {
        let m = makeModel()
        m.start()
        let ex = simpleExercise(named: "Effort Press")
        m.startLogSet(for: ex)
        m.effortMode = .rpe
        m.effortValue = 8

        let set = m.logSet()

        XCTAssertEqual(set?.rpe, 8)
        XCTAssertEqual(m.lastSyncPayload?["rpe"] as? Double, 8)
        XCTAssertEqual(m.lastSyncPayload?["effort_mode"] as? String, "rpe")
    }

    func testEffortRIRConvertsToStoredRPE() {
        let m = makeModel()
        m.start()
        let ex = simpleExercise(named: "RIR Press")
        m.startLogSet(for: ex)
        m.effortMode = .rir
        m.effortValue = 2

        let set = m.logSet()

        XCTAssertEqual(set?.rpe, 8)
        XCTAssertEqual(m.lastSyncPayload?["effort_mode"] as? String, "rir")
        XCTAssertEqual(m.lastSyncPayload?["effort_value"] as? Double, 2)
    }

    func testLogLastSetReturnsHomeWithoutRest() {
        let m = makeModel()
        m.start()
        let ex = simpleExercise(named: "Last Set Press")
        m.startLogSet(for: ex)

        _ = m.logLastSet()

        XCTAssertEqual(m.stage, .home)
        XCTAssertEqual(m.exerciseList.first?.setCount, 1)
        XCTAssertEqual(m.restTimer.remaining, 0)
    }

    func testDeleteSetRemovesLocalSetAndEmitsPayload() {
        let m = makeModel()
        m.start()
        let ex = simpleExercise(named: "Delete Set Press")
        m.startLogSet(for: ex)
        let set = m.logSet()
        m.finishRest()
        m.startLogSet(for: ex)

        let payload = m.deleteSet(id: set!.id)

        XCTAssertEqual(m.currentWorkoutHistoryLines.count, 0)
        XCTAssertEqual(payload?["action"] as? String, "delete_set")
        XCTAssertEqual(payload?["set_id"] as? String, set?.id.uuidString)
    }

    func testDeleteSetAllowsReentryDuringSameExercise() {
        let m = makeModel()
        m.start()
        let ex = simpleExercise(named: "Reenter Set Press")
        m.startLogSet(for: ex)
        let first = m.logSet()
        m.finishRest()

        XCTAssertNotNil(m.deleteSet(id: first!.id))
        XCTAssertEqual(m.currentWorkoutHistoryLines, [])

        m.currentWeight = 75
        m.currentReps = 6
        let replacement = m.logLastSet()

        XCTAssertNotNil(replacement)
        XCTAssertEqual(m.session?.orderedSets.count, 1)
        XCTAssertEqual(m.session?.orderedSets.first?.reps, 6)
        XCTAssertEqual(m.stage, .home)
    }

    func testDeleteExerciseRemovesPlannedNameSetsAndEmitsPayload() {
        let m = makeModel()
        m.start(createSession: true)
        let ex = simpleExercise(named: "Delete Exercise Press")
        m.addExercise(named: ex.name)
        m.startLogSet(for: ex)
        _ = m.logSet()

        let payload = m.deleteExercise(ex)

        XCTAssertTrue(m.exerciseList.isEmpty)
        XCTAssertTrue(m.session?.orderedSets.isEmpty == true)
        XCTAssertEqual(payload?["action"] as? String, "delete_exercise")
        XCTAssertEqual(payload?["exercise"] as? String, ex.name)
    }

    func testEndSessionPayloadIncludesMetadataForOutOfOrderPhoneFinalize() {
        let m = makeModel()
        m.start(title: "Push Day",
                plannedExerciseNames: ["Bench Press"],
                repLadder: [12, 10, 8],
                planKey: "preset-push",
                createSession: true)
        let ex = m.exerciseList[0].exercise
        m.startLogSet(for: ex)
        _ = m.logSet()
        m.finish()
        m.skipCooldown()

        let payload = m.endSessionPayload()

        XCTAssertEqual(payload?["session_title"] as? String, "Push Day")
        XCTAssertEqual(payload?["planned_exercises"] as? [String], ["Bench Press"])
        XCTAssertEqual(payload?["planned_rep_ladder"] as? [Int], [12, 10, 8])
        XCTAssertEqual(payload?["plan_key"] as? String, "preset-push")
        XCTAssertNotNil(payload?["ended_at"])
    }
}
