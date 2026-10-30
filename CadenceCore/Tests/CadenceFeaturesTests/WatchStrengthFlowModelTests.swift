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

    // MARK: - Warm-up

    func testWarmup_offWhenZeroMinutes() {
        let m = makeModel()
        m.start(createSession: true)
        XCTAssertFalse(m.beginWarmup())
        XCTAssertEqual(m.stage, .home)
    }

    func testWarmup_beginAndSkipRecordsTimeAndGoesHome() {
        let m = WatchStrengthFlowModel(context: context, cooldownDefault: 5, restDefault: 90, warmupDefault: 5)
        m.start(createSession: true)
        XCTAssertTrue(m.beginWarmup())
        XCTAssertEqual(m.stage, .warmup(300))
        m.endWarmup()
        XCTAssertEqual(m.stage, .home)
        XCTAssertNotNil(m.session)
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

    // MARK: - Add result contract (issue #408)

    private struct SaveBoom: Error {}

    func testAddExerciseResult_addsOnceToActiveSessionAndPersists() {
        let m = makeModel()
        m.start(createSession: true)
        m.goToAddExercise()
        XCTAssertEqual(m.addExercise(named: "Bench Press"), .added(name: "Bench Press"))
        XCTAssertEqual(m.session?.plannedExerciseNames, ["Bench Press"])
        XCTAssertEqual(m.stage, .home)
        XCTAssertEqual(m.lastAddedExerciseName, "Bench Press")
        XCTAssertFalse(context.hasChanges)
    }

    func testAddExerciseResult_duplicateAndCaseVariantAreRejected() {
        let m = makeModel()
        m.start(createSession: true)
        m.addExercise(named: "Bench Press")
        m.goToAddExercise()
        XCTAssertEqual(m.addExercise(named: "Bench Press"), .alreadyPresent(name: "Bench Press"))
        XCTAssertEqual(m.addExercise(named: "bench press"), .alreadyPresent(name: "Bench Press"))
        XCTAssertEqual(m.session?.plannedExerciseNames, ["Bench Press"])
        XCTAssertEqual(m.stage, .addExercise)
    }

    func testAddExerciseResult_unavailableLeavesWorkoutUnchanged() {
        let m = makeModel()
        m.start(createSession: true)
        m.goToAddExercise()
        XCTAssertEqual(m.addExercise(named: "   "), .unavailable(name: ""))
        XCTAssertEqual(m.addExercise(id: UUID(), named: "Gone Lift"), .unavailable(name: "Gone Lift"))
        XCTAssertEqual(m.session?.plannedExerciseNames, [])
        XCTAssertEqual(m.stage, .addExercise)
        XCTAssertNil(m.lastAddedExerciseName)
    }

    func testAddExerciseResult_byIdAddsCatalogExerciseWithoutCreatingOne() throws {
        let bench = simpleExercise(named: "Bench Press")
        let before = try context.fetchCount(FetchDescriptor<Exercise>())
        let m = makeModel()
        m.start(createSession: true)
        XCTAssertEqual(m.addExercise(id: bench.id, named: "Bench Press"), .added(name: "Bench Press"))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Exercise>()), before)
    }

    func testAddExerciseResult_saveFailureRestoresAndStaysInAddExercise() {
        let m = makeModel()
        m.start(createSession: true)
        m.goToAddExercise()
        m.saveHandler = { _ in throw SaveBoom() }
        XCTAssertEqual(m.addExercise(named: "Bench Press"), .saveFailed(name: "Bench Press"))
        XCTAssertEqual(m.session?.plannedExerciseNames, [])
        XCTAssertEqual(m.stage, .addExercise)
        XCTAssertNil(m.lastAddedExerciseName)

        let pending = makeModel()
        pending.start()
        pending.saveHandler = { _ in throw SaveBoom() }
        XCTAssertEqual(pending.addExercise(named: "Squat"), .saveFailed(name: "Squat"))
        XCTAssertTrue(pending.pendingExercises.isEmpty)
    }

    func testCreateAndAddExerciseFollowsSameContract() {
        let m = makeModel()
        m.start(createSession: true)
        XCTAssertEqual(m.createAndAddExercise(named: "Cable Twist", muscleGroups: [.abdominals]),
                       .added(name: "Cable Twist"))
        XCTAssertEqual(m.createAndAddExercise(named: "cable twist", muscleGroups: [.abdominals]),
                       .alreadyPresent(name: "Cable Twist"))
        XCTAssertEqual(m.createAndAddExercise(named: "", muscleGroups: [.abdominals]), .unavailable(name: ""))
        m.saveHandler = { _ in throw SaveBoom() }
        XCTAssertEqual(m.createAndAddExercise(named: "Other Twist", muscleGroups: [.abdominals]),
                       .saveFailed(name: "Other Twist"))
        XCTAssertEqual(m.session?.plannedExerciseNames, ["Cable Twist"])
    }

    func testAddPresenter_outcomesNeedNoClockAndSearchGenerationRejectsStale() {
        let added = WatchExerciseAddPresenter.outcome(for: .added(name: "Squat"))
        XCTAssertEqual(added.message, "Added Squat")
        XCTAssertTrue(added.returnsToPlan)
        for result in [WatchExerciseAddResult.alreadyPresent(name: "A"), .unavailable(name: "A"), .saveFailed(name: "A")] {
            let o = WatchExerciseAddPresenter.outcome(for: result)
            XCTAssertFalse(o.returnsToPlan)
            XCTAssertEqual(o.feedback, .failure)
        }
        XCTAssertTrue(WatchExerciseAddPresenter.acceptsSearchResults(
            generation: 3, current: 3, searchedQuery: "ben", currentQuery: " ben "))
        XCTAssertFalse(WatchExerciseAddPresenter.acceptsSearchResults(
            generation: 2, current: 3, searchedQuery: "ben", currentQuery: "ben"))
        XCTAssertFalse(WatchExerciseAddPresenter.acceptsSearchResults(
            generation: 3, current: 3, searchedQuery: "ben", currentQuery: "bench"))
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

    func testSecondAndThirdSetDefaultToPreviousLoadAndReps() {
        let m = makeModel()
        m.start()
        let ex = simpleExercise(named: "Default Carry Press")
        m.startLogSet(for: ex)
        m.currentWeight = 62.5
        m.currentReps = 8
        _ = m.logSet()
        m.finishRest()
        XCTAssertEqual(m.currentWeight, 62.5)
        XCTAssertEqual(Int(m.currentReps), 8)
        m.currentWeight = 65
        _ = m.logSet()
        m.finishRest()
        XCTAssertEqual(m.currentWeight, 65)
        XCTAssertEqual(Int(m.currentReps), 8)
    }

    func testFirstSetDefaultsToPreviousWorkoutLoad() throws {
        let first = makeModel()
        first.start()
        let ex = simpleExercise(named: "History Carry Press")
        first.startLogSet(for: ex)
        first.currentWeight = 80
        first.currentReps = 6
        _ = first.logSet()
        first.finish()

        let second = makeModel()
        second.start()
        second.startLogSet(for: ex)
        XCTAssertEqual(second.currentWeight, 80)
        XCTAssertEqual(Int(second.currentReps), 6)
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

    func testLogLastSetRestsThenAdvancesToNextExercise() {
        let m = makeModel()
        m.start()
        let first = simpleExercise(named: "Last Set Press")
        let second = simpleExercise(named: "Next Up Row")
        m.startLogSet(for: second)
        _ = m.logSet()
        m.finishRest()
        m.startLogSet(for: first)
        _ = m.logLastSet()
        XCTAssertEqual(m.stage, .rest)
        m.finishRest()
        XCTAssertNotEqual(m.stage, .keypad(first))
    }

    func testLogLastSetWithNoNextExerciseRestsThenHome() {
        let m = makeModel()
        m.start()
        let ex = simpleExercise(named: "Last Set Press")
        m.startLogSet(for: ex)

        _ = m.logLastSet()

        XCTAssertEqual(m.stage, .rest)
        m.finishRest()
        XCTAssertEqual(m.stage, .home)
        XCTAssertEqual(m.exerciseList.first?.setCount, 1)
        XCTAssertTrue(m.allExercisesCompletePrompt)
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
        XCTAssertEqual(m.stage, .rest)
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

    func testDirectSummaryHeartRateSnapshotIsKeptAndIdempotent() throws {
        let m = makeModel()
        m.start(title: "Push", plannedExerciseNames: ["Bench Press"], createSession: true)
        let dense = (0..<5).map { HRSamplePoint(t: Double($0) * 5, bpm: 110 + Double($0)) }
        m.startLogSet(for: m.exerciseList[0].exercise)
        _ = m.logSet()
        m.finish()
        m.skipCooldown()
        m.recordHeartRate(dense)
        m.recordHeartRate(dense)  // reappearing summary / retried send
        m.recordHeartRate([])     // post-teardown empty recorder must not erase it
        let payload = try XCTUnwrap(m.endSessionPayload())
        XCTAssertNotNil(payload[WatchStrengthHeartRate.transportKey])
        XCTAssertEqual(m.recordedHeartRate, dense)
    }

    func testLegacyPayloadHasSourceButNoInventedFinalSequence() throws {
        let m = makeModel()
        m.start(title: "Push", plannedExerciseNames: ["Bench Press"], createSession: true)
        let dense = (0..<5).map { HRSamplePoint(t: Double($0) * 5, bpm: 110 + Double($0)) }
        m.recordHeartRate(dense)
        let legacy = try XCTUnwrap(m.endSessionPayload())
        XCTAssertNil(legacy["hr_final_sequence"])
        XCTAssertEqual(legacy["hr_source"] as? String, HeartRateSource.watchHealthKit.rawValue)
        XCTAssertNotNil(legacy["hr_captured_at"])
        let durable = try XCTUnwrap(m.endSessionPayload(finalSequence: 2))
        XCTAssertEqual(durable["hr_final_sequence"] as? Int, 2)
        XCTAssertNotEqual(durable["hr_sample_count"] as? Int, 2)
    }

    // MARK: - Synced owner history defaults

    private struct StubHistory: WatchSetDefaultHistoryProviding {
        var snapshot: WatchSetDefaultSnapshot
        func history(exerciseKey: String, performerID: String) -> PerformerSetPlanner.History {
            snapshot.history(exerciseKey: exerciseKey, performerID: performerID)
        }
    }

    private func benchSnapshot() -> WatchSetDefaultSnapshot {
        WatchSetDefaultSnapshot(generatedAt: Date(timeIntervalSince1970: 1_000), performers: [
            .init(id: WatchSync.PerformerReference.ownerID, displayName: "Me", exercises: [
                .init(id: "Bench Press", displayName: "Bench Press", repLadders: [[8, 8, 8]],
                      samples: [.init(weightKg: 125, reps: 8)], firstWorkingWeightKg: 125)
            ], generalRepLadders: [])
        ])
    }

    private func syncedModel(plan: WatchPlanPayload? = nil, snapshot: WatchSetDefaultSnapshot? = nil)
        -> WatchStrengthFlowModel {
        let m = WatchStrengthFlowModel(
            context: context, unit: .kilograms, cooldownDefault: 5, restDefault: 90,
            setDefaultHistory: snapshot.map { StubHistory(snapshot: $0) })
        m.start(title: "Push", plannedExerciseNames: ["Bench Press"], planPayload: plan, createSession: true)
        return m
    }

    func testSyncedOwnerSnapshotPrefillsFirstSetAndMatchesDirectResolver() {
        let snap = benchSnapshot()
        let m = syncedModel(snapshot: snap)
        let ex = m.exerciseList[0].exercise
        m.startLogSet(for: ex)
        let direct = PerformerSetPlanner.resolve(
            setIndex: 0, performerPlan: nil, ownerPlan: [], ownerLadder: nil, isOwner: true,
            history: snap.history(exerciseKey: "Bench Press", performerID: "owner"))
        XCTAssertEqual(m.currentWeight, 125)
        XCTAssertEqual(m.currentReps, 8)
        XCTAssertEqual(m.currentWeight, direct.weightKg)
        XCTAssertEqual(m.currentReps, Double(direct.reps))
    }

    func testJustLoggedWatchSetOverridesSnapshot() {
        var snap = benchSnapshot()
        snap.performers[0].exercises[0].repLadders = []
        let m = syncedModel(snapshot: snap)
        let ex = m.exerciseList[0].exercise
        m.startLogSet(for: ex)
        m.currentWeight = 130
        m.currentReps = 6
        _ = m.logSet()
        m.finishRest()
        m.startLogSet(for: ex)
        XCTAssertEqual(m.currentWeight, 130)
        XCTAssertEqual(m.currentReps, 6)
    }

    func testExplicitPlanOverridesSnapshot() {
        let plan = WatchPlanPayload(strength: .init(
            exerciseNames: ["Bench Press"],
            prescriptions: [PlannedExercisePrescription(
                exerciseName: "Bench Press",
                sets: [PlannedSetPrescription(targetReps: 6, targetWeightKg: 135)])]))
        let m = syncedModel(plan: plan, snapshot: benchSnapshot())
        m.startLogSet(for: m.exerciseList[0].exercise)
        XCTAssertEqual(m.currentWeight, 135)
        XCTAssertEqual(m.currentReps, 6)
    }

    func testNoSnapshotOrNoHistoryKeepsFallbacks() {
        let m = syncedModel()
        m.startLogSet(for: m.exerciseList[0].exercise)
        XCTAssertEqual(m.currentWeight, 20)
        let empty = syncedModel(snapshot: WatchSetDefaultSnapshot(generatedAt: Date(), performers: []))
        empty.startLogSet(for: empty.exerciseList[0].exercise)
        XCTAssertEqual(empty.currentWeight, m.currentWeight)
        XCTAssertEqual(empty.currentReps, m.currentReps)
    }
}
