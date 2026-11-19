#if canImport(SwiftData)
import Foundation
import Testing
import SwiftData
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures
import CadenceCore
import CadencePhoneFeatures

final class WatchStrengthFlowModelTests {

    private nonisolated(unsafe) var container: ModelContainer!
    private nonisolated(unsafe) var context: ModelContext!

    init() throws {
        container = try CadenceStore.makeModelContainer(inMemory: true)
        context = ModelContext(container)
        _ = try WorkoutRepository.seedStarterLibraryIfNeeded(context)
    }

    deinit {
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

    @Test func warmup_offWhenZeroMinutes() {
        let m = makeModel()
        m.start(createSession: true)
        #expect(!m.beginWarmup())
        #expect(m.stage == .home)
    }

    @Test func warmup_beginAndSkipRecordsTimeAndGoesHome() {
        let m = WatchStrengthFlowModel(context: context, cooldownDefault: 5, restDefault: 90, warmupDefault: 5)
        m.start(createSession: true)
        #expect(m.beginWarmup())
        #expect(m.stage == .warmup(300))
        m.endWarmup()
        #expect(m.stage == .home)
        #expect(m.session != nil)
    }

    // MARK: - Stage transitions

    @Test func start_showsHome() {
        let m = makeModel()
        m.start()
        #expect(m.stage == .home)
        #expect(m.session == nil)
    }

    @Test func goToAddExercise() {
        let m = makeModel()
        m.start()
        m.goToAddExercise()
        if case .addExercise = m.stage {} else { Issue.record("Expected addExercise stage") }
    }

    @Test func addExercise_returnsToHome() {
        let m = makeModel()
        m.start()
        m.addExercise(named: "Bench Press")
        #expect(m.pendingExercises == ["Bench Press"])
        #expect(m.stage == .home)
    }

    @Test func newBodyweightExerciseDefaultsToBodyweightInsteadOfBarbellFallback() {
        let m = makeModel()
        m.start(title: "Bodyweight", plannedExerciseNames: ["Push-Up"], createSession: true)
        guard let pushUp = m.exerciseList.first?.exercise else {
            Issue.record("Missing Push-Up")
            return
        }

        m.startLogSet(for: pushUp)

        #expect(m.currentWeight == 0)
    }

    @Test func mountainClimbersShowBWAndNeverLogAnExternalLoad() throws {
        let model = makeModel()
        model.start(title: "Bodyweight", plannedExerciseNames: ["Mountain Climbers"], createSession: true)
        let exercise = try #require(model.exerciseList.first?.exercise)
        model.startLogSet(for: exercise)
        let card = try #require(model.setCardState)
        #expect(card.isNonWeighted)
        #expect(card.weightText == "BW")
        // Even stale imported/planned weights cannot leak into the saved set.
        model.currentWeight = 20
        let set = try #require(model.logSet())
        #expect(set.weight == 0)
        #expect(set.usesBodyweight == true)
    }

    @Test func loggedSetContextIsFrozenBeforeRestAdvancesToNextExercise() {
        let m = makeModel()
        m.start(title: "Test", plannedExerciseNames: ["Bench Press", "Squat"], createSession: true)
        guard let bench = m.exerciseList.first(where: { $0.exercise.name == "Bench Press" })?.exercise else {
            Issue.record("Missing bench")
            return
        }
        m.startLogSet(for: bench)
        m.currentWeight = 80
        m.currentReps = 5
        guard let logged = m.logSet() else {
            Issue.record("Set did not log")
            return
        }

        #expect(m.lastLoggedSetContext ==
                       WatchLoggedSetContext(exerciseName: "Bench Press",
                                             weightKg: logged.effectiveLoadKg,
                                             reps: logged.reps))
    }

    // MARK: - Add result contract (issue #408)

    private struct SaveBoom: Error {}

    @Test func addExerciseResult_addsOnceToActiveSessionAndPersists() {
        let m = makeModel()
        m.start(createSession: true)
        m.goToAddExercise()
        #expect(m.addExercise(named: "Bench Press") == .added(name: "Bench Press"))
        #expect(m.session?.plannedExerciseNames == ["Bench Press"])
        #expect(m.stage == .home)
        #expect(m.lastAddedExerciseName == "Bench Press")
        #expect(!context.hasChanges)
    }

    @Test func addExerciseResult_duplicateAndCaseVariantAreRejected() {
        let m = makeModel()
        m.start(createSession: true)
        m.addExercise(named: "Bench Press")
        m.goToAddExercise()
        #expect(m.addExercise(named: "Bench Press") == .alreadyPresent(name: "Bench Press"))
        #expect(m.addExercise(named: "bench press") == .alreadyPresent(name: "Bench Press"))
        #expect(m.session?.plannedExerciseNames == ["Bench Press"])
        #expect(m.stage == .addExercise)
    }

    @Test func addExerciseResult_unavailableLeavesWorkoutUnchanged() {
        let m = makeModel()
        m.start(createSession: true)
        m.goToAddExercise()
        #expect(m.addExercise(named: "   ") == .unavailable(name: ""))
        #expect(m.addExercise(id: UUID(), named: "Gone Lift") == .unavailable(name: "Gone Lift"))
        #expect(m.session?.plannedExerciseNames == [])
        #expect(m.stage == .addExercise)
        #expect(m.lastAddedExerciseName == nil)
    }

    @Test func addExerciseResult_byIdAddsCatalogExerciseWithoutCreatingOne() throws {
        let bench = simpleExercise(named: "Bench Press")
        let before = try context.fetchCount(FetchDescriptor<Exercise>())
        let m = makeModel()
        m.start(createSession: true)
        #expect(m.addExercise(id: bench.id, named: "Bench Press") == .added(name: "Bench Press"))
        #expect(try context.fetchCount(FetchDescriptor<Exercise>()) == before)
    }

    @Test func addSuggestedExercise_attachesPrescriptionAndAddsOnce() {
        let bench = simpleExercise(named: "Bench Press")
        let m = makeModel()
        m.start(createSession: true)
        #expect(m.addSuggestedExercise(id: bench.id, name: "Bench Press", sets: 3, repRange: 8...12) ==
                       .added(name: "Bench Press"))
        #expect(m.session?.plannedExerciseNames == ["Bench Press"])
        let rx = m.session?.plannedPrescriptions.first
        #expect(m.session?.plannedPrescriptions.count == 1)
        #expect(rx?.exerciseName == "Bench Press")
        #expect(rx?.sets.count == 3)
        #expect(rx?.sets.first?.targetReps == 8)
        #expect(m.stage == .home)
    }

    @Test func addSuggestedExercise_unavailableNeverCreatesByName() throws {
        let before = try context.fetchCount(FetchDescriptor<Exercise>())
        let m = makeModel()
        m.start(createSession: true)
        #expect(m.addSuggestedExercise(id: UUID(), name: "Ghost Lift", sets: 3, repRange: 8...12) ==
                       .unavailable(name: "Ghost Lift"))
        #expect(m.session?.plannedExerciseNames == [])
        #expect(m.session?.plannedPrescriptions.count == 0)
        #expect(try context.fetchCount(FetchDescriptor<Exercise>()) == before)
    }

    @Test func addSuggestedExercise_saveFailureRestoresPrescriptions() {
        let bench = simpleExercise(named: "Bench Press")
        let m = makeModel()
        m.start(createSession: true)
        m.saveHandler = { _ in throw SaveBoom() }
        #expect(m.addSuggestedExercise(id: bench.id, name: "Bench Press", sets: 3, repRange: 8...12) ==
                       .saveFailed(name: "Bench Press"))
        #expect(m.session?.plannedExerciseNames == [])
        #expect(m.session?.plannedPrescriptions.count == 0)
    }

    @Test func suggestedCard_resolvesByNameAndFormatsPrescription() {
        let entry = ExerciseCatalogEntry(id: UUID(), name: "Bench Press",
                                         summaryMuscleGroups: [.chest])
        let catalog = ExerciseCatalogSnapshot(entries: [entry], recent: [])
        let hit = SuggestedWorkoutExercise(candidateID: "x", name: "bench press", mechanics: .compound,
                                           plannedSets: 3, repRange: 8...12, contributions: [], selectionScore: 1)
        let miss = SuggestedWorkoutExercise(candidateID: "y", name: "Ghost", mechanics: .compound,
                                            plannedSets: 2, repRange: 5...5, contributions: [], selectionScore: 1)
        #expect(WatchSuggestedExerciseCard.resolve(hit, in: catalog)?.id == entry.id)
        #expect(WatchSuggestedExerciseCard.resolve(miss, in: catalog) == nil)
        #expect(WatchSuggestedExerciseCard.prescriptionText(hit) == "3 sets · 8–12 reps")
        #expect(WatchSuggestedExerciseCard.prescriptionText(miss) == "2 sets · 5 reps")
    }

    @Test func addExerciseResult_saveFailureRestoresAndStaysInAddExercise() {
        let m = makeModel()
        m.start(createSession: true)
        m.goToAddExercise()
        m.saveHandler = { _ in throw SaveBoom() }
        #expect(m.addExercise(named: "Bench Press") == .saveFailed(name: "Bench Press"))
        #expect(m.session?.plannedExerciseNames == [])
        #expect(m.stage == .addExercise)
        #expect(m.lastAddedExerciseName == nil)

        let pending = makeModel()
        pending.start()
        pending.saveHandler = { _ in throw SaveBoom() }
        #expect(pending.addExercise(named: "Squat") == .saveFailed(name: "Squat"))
        #expect(pending.pendingExercises.isEmpty)
    }

    @Test func createAndAddExerciseFollowsSameContract() {
        let m = makeModel()
        m.start(createSession: true)
        #expect(m.createAndAddExercise(named: "Cable Twist", muscleGroups: [.abdominals]) ==
                       .added(name: "Cable Twist"))
        #expect(m.createAndAddExercise(named: "cable twist", muscleGroups: [.abdominals]) ==
                       .alreadyPresent(name: "Cable Twist"))
        #expect(m.createAndAddExercise(named: "", muscleGroups: [.abdominals]) == .unavailable(name: ""))
        m.saveHandler = { _ in throw SaveBoom() }
        #expect(m.createAndAddExercise(named: "Other Twist", muscleGroups: [.abdominals]) ==
                       .saveFailed(name: "Other Twist"))
        #expect(m.session?.plannedExerciseNames == ["Cable Twist"])
    }

    @Test func createAndAddCustomExercisePersistsPrimaryAndSecondaryMuscles() {
        let model = makeModel()
        model.start(createSession: true)
        #expect(
            model.createAndAddExercise(
                named: "Ring Push-up",
                attribution: .init(primary: [.chest, .triceps], secondary: [.shoulders, .abdominals])) ==
            .added(name: "Ring Push-up"))
        let exercise = try! WorkoutRepository.findOrCreateExercise(named: "Ring Push-up", in: context)
        #expect(exercise.primaryMuscles == ["chest", "triceps"])
        #expect(exercise.secondaryMuscles == ["shoulders", "abdominals"])
    }

    @Test func createAndAddCustomExerciseRejectsSecondaryOnly() {
        let model = makeModel()
        model.start(createSession: true)
        #expect(
            model.createAndAddExercise(named: "Ghost", attribution: .init(secondary: [.shoulders])) ==
            .unavailable(name: "Ghost"))
    }

    @Test func addPresenter_outcomesNeedNoClockAndSearchGenerationRejectsStale() {
        let added = WatchExerciseAddPresenter.outcome(for: .added(name: "Squat"))
        #expect(added.message == "Added Squat")
        #expect(added.returnsToPlan)
        for result in [WatchExerciseAddResult.alreadyPresent(name: "A"), .unavailable(name: "A"), .saveFailed(name: "A")] {
            let o = WatchExerciseAddPresenter.outcome(for: result)
            #expect(!o.returnsToPlan)
            #expect(o.feedback == .failure)
        }
        #expect(WatchExerciseAddPresenter.acceptsSearchResults(
            generation: 3, current: 3, searchedQuery: "ben", currentQuery: " ben "))
        #expect(!WatchExerciseAddPresenter.acceptsSearchResults(
            generation: 2, current: 3, searchedQuery: "ben", currentQuery: "ben"))
        #expect(!WatchExerciseAddPresenter.acceptsSearchResults(
            generation: 3, current: 3, searchedQuery: "ben", currentQuery: "bench"))
    }

    @Test func addCustomExerciseCreatesFacetedExerciseAndAddsItToWorkout() {
        let m = makeModel()
        m.start(createSession: true)

        let exercise = m.addCustomExercise(named: "  Standing Cable Twist  ",
                                           muscleGroups: [.abdominals, .shoulders])

        #expect(exercise?.name == "Standing Cable Twist")
        #expect(exercise?.isCustom == true)
        #expect(Set(exercise?.primaryMuscles ?? []) == ["shoulders", "abdominals"])
        #expect(exercise?.categoryValue == .other)
        #expect(m.stage == .home)
        #expect(m.exerciseList.contains { $0.exercise.name == "Standing Cable Twist" })
    }

    @Test func addCustomExerciseRequiresNameAndMuscleGroup() {
        let m = makeModel()
        m.start(createSession: true)
        #expect(m.addCustomExercise(named: "", muscleGroups: [.lats]) == nil)
        #expect(m.addCustomExercise(named: "Mystery Lift", muscleGroups: []) == nil)
    }

    @Test func addExercise_showsPendingExerciseOnHome() {
        let m = makeModel()
        m.start()
        m.addExercise(named: "Bench Press")
        #expect(m.exerciseList.map { $0.exercise.name } == ["Bench Press"])
        #expect(m.exerciseList.first?.setCount == 0)
    }

    @Test func addExerciseAliasStoresCanonicalBuiltInName() {
        let m = makeModel()
        m.start()
        m.addExercise(named: "Tricep Pushdown")
        #expect(m.pendingExercises == ["Triceps Pushdown"])
        #expect(m.exerciseList.map { $0.exercise.name } == ["Triceps Pushdown"])
        #expect(m.exerciseList.first?.exercise.primaryMuscles == ["triceps"])
    }

    @Test func plannedAliasLogSetPayloadUsesCanonicalBuiltInName() {
        let m = makeModel()
        m.start(
            title: "Shoulders",
            plannedExerciseNames: ["Lateral Raise"],
            createSession: true
        )
        #expect(m.session?.plannedExerciseNames == ["Dumbbell Lateral Raise"])
        #expect(m.exerciseList.map { $0.exercise.name } == ["Dumbbell Lateral Raise"])

        let exercise = m.exerciseList[0].exercise
        m.startLogSet(for: exercise)
        _ = m.logSet()

        #expect(m.lastSyncPayload?["exercise"] as? String == "Dumbbell Lateral Raise")
        #expect(m.lastSyncPayload?["planned_exercises"] as? [String] == ["Dumbbell Lateral Raise"])
    }

    @Test func logSetFromAddedExercise_createsSessionAndKeepsExerciseVisible() {
        let m = makeModel()
        m.start()
        m.addExercise(named: "Bench Press")
        let ex = m.exerciseList[0].exercise
        m.startLogSet(for: ex)
        _ = m.logSet()
        m.finishRest()
        #expect(m.session != nil)
        #expect(m.pendingExercises == [])
        #expect(m.exerciseList.map { $0.exercise.name } == ["Bench Press"])
        #expect(m.exerciseList.first?.setCount == 1)
    }

    @Test func queuedExercisesSurviveFirstLoggedSet() {
        let m = makeModel()
        m.start()
        m.addExercise(named: "Bench Press")
        m.addExercise(named: "Squat")
        let ex = m.exerciseList[0].exercise
        m.startLogSet(for: ex)
        _ = m.logSet()
        m.finishRest()
        #expect(m.exerciseList.map { $0.exercise.name } == ["Bench Press", "Squat"])
        #expect(m.exerciseList.map { $0.setCount } == [1, 0])
    }

    @Test func finishAfterOnlyAddingExercise_discardsEmptySession() {
        let m = makeModel()
        m.start()
        m.addExercise(named: "Bench Press")
        m.finish()
        #expect(m.stage == .discarded)
        #expect(m.session == nil)
    }

    @Test func logSet_createsSessionLazily() {
        let m = makeModel()
        m.start()
        let ex = try! WorkoutRepository.findOrCreateExercise(named: "TestPress", equipment: nil, in: context)
        m.startLogSet(for: ex)
        _ = m.logSet()
        #expect(m.session != nil)
        #expect(m.stage == .rest)
    }

    @Test func logSetGoesToRestAndNextSetReturnsToSameExercise() {
        let m = makeModel()
        m.start(repLadder: [12, 10, 8], createSession: true)
        let ex = simpleExercise(named: "Rest Return Press")
        m.startLogSet(for: ex)
        #expect(Int(m.currentReps) == 12)

        _ = m.logSet()
        #expect(m.stage == .rest)

        m.finishRest()
        guard case .keypad(let returnedExercise) = m.stage else {
            Issue.record("Expected Next Set to return to the same exercise keypad")
            return
        }
        #expect(returnedExercise.id == ex.id)
        #expect(Int(m.currentReps) == 10)
    }

    @Test func secondAndThirdSetDefaultToPreviousLoadAndReps() {
        let m = makeModel()
        m.start()
        let ex = simpleExercise(named: "Default Carry Press")
        m.startLogSet(for: ex)
        m.currentWeight = 62.5
        m.currentReps = 8
        _ = m.logSet()
        m.finishRest()
        #expect(m.currentWeight == 62.5)
        #expect(Int(m.currentReps) == 8)
        m.currentWeight = 65
        _ = m.logSet()
        m.finishRest()
        #expect(m.currentWeight == 65)
        #expect(Int(m.currentReps) == 8)
    }

    @Test func firstSetDefaultsToPreviousWorkoutLoad() throws {
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
        #expect(second.currentWeight == 80)
        #expect(Int(second.currentReps) == 6)
    }

    @Test func startCreateSessionPrefillsPlannedExercisesAndLadder() {
        let m = makeModel()
        m.start(title: "Push Day",
                plannedExerciseNames: ["Bench Press", "Back Squat"],
                repLadder: [12, 10, 8],
                planKey: "preset-push",
                createSession: true)

        #expect(m.session?.title == "Push Day")
        #expect(m.session?.plannedExerciseNames == ["Bench Press", "Back Squat"])
        #expect(m.session?.plannedRepLadder == [12, 10, 8])
        #expect(m.session?.planKey == "preset-push")
        #expect(m.exerciseList.map { $0.exercise.name } == ["Bench Press", "Back Squat"])
        #expect(m.exerciseList.map { $0.setCount } == [0, 0])
    }

    @Test func startWithVersionedPlanPayloadKeepsRichPrescriptionAndTransportData() {
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

        #expect(m.session?.planSessionID == sessionID)
        #expect(m.session?.plannedPrescriptions.first?.exerciseKey == "bench_press")
        #expect(m.session?.plannedPrescriptions.first?.sets.first?.restSeconds == 150)
        #expect(m.session?.plannedExerciseNames == ["Bench Press"])
    }

    @Test func logSet_ownerSet_countsVolume() {
        let m = makeModel()
        m.start()
        let ex = try! WorkoutRepository.findOrCreateExercise(named: "TestPress", equipment: nil, in: context)
        m.currentWeight = 100; m.currentReps = 5
        m.startLogSet(for: ex)
        _ = m.logSet()
        #expect(m.setCount == 1)
        #expect(m.volume > 0)
    }

    @Test func warmupSet_excludedFromVolume() {
        let m = makeModel()
        m.start()
        let ex = try! WorkoutRepository.findOrCreateExercise(named: "TestPress", equipment: nil, in: context)
        m.startLogSet(for: ex)
        m.toggleWarmup()
        m.currentWeight = 60; m.currentReps = 10
        _ = m.logSet()
        #expect(m.setCount == 0)
        #expect(abs(m.volume - 0) <= 0.1)
    }

    @Test func logSetPayload_includesWarmupFlag() {
        let m = makeModel()
        m.start()
        let ex = try! WorkoutRepository.findOrCreateExercise(named: "TestPress", equipment: nil, in: context)
        m.startLogSet(for: ex)
        m.toggleWarmup()
        _ = m.logSet()
        #expect(m.lastSyncPayload?["is_warmup"] as? Bool == true)
    }

    @Test func finish_withSets_transitionsToCooldown() {
        let m = makeModel()
        m.start()
        let ex = try! WorkoutRepository.findOrCreateExercise(named: "TestPress", equipment: nil, in: context)
        m.startLogSet(for: ex)
        _ = m.logSet()
        m.finish()
        if case .cooldown = m.stage {} else { Issue.record("Expected cooldown stage") }
    }

    @Test func finish_emptySession_autoDiscards() {
        let m = makeModel()
        m.start()
        m.finish()
        #expect(m.stage == .discarded)
    }

    @Test func skipCooldown_goesToSummary() {
        let m = makeModel()
        m.start()
        let ex = try! WorkoutRepository.findOrCreateExercise(named: "TestPress", equipment: nil, in: context)
        m.startLogSet(for: ex)
        _ = m.logSet()
        m.finish()
        m.skipCooldown()
        #expect(m.stage == .summary)
    }

    @Test func completeCooldown_goesToSummary() {
        let m = makeModel()
        m.start()
        let ex = try! WorkoutRepository.findOrCreateExercise(named: "TestPress", equipment: nil, in: context)
        m.startLogSet(for: ex)
        _ = m.logSet()
        m.finish()
        m.completeCooldown()
        #expect(m.stage == .summary)
    }

    @Test func cancel_beforeCreate_noDiscardPayload() {
        let m = makeModel()
        m.start()
        m.cancel()
        #expect(m.stage == .discarded)
        #expect(m.discardPayload == nil)
    }

    @Test func cancel_afterSync_emitsDiscardPayload() {
        let m = makeModel()
        m.start()
        let ex = try! WorkoutRepository.findOrCreateExercise(named: "TestPress", equipment: nil, in: context)
        m.startLogSet(for: ex)
        _ = m.logSet()
        m.cancel()
        #expect(m.stage == .discarded)
        #expect(m.discardPayload != nil)
        #expect(m.discardPayload?["action"] as? String == "discard_session")
    }

    // MARK: - Partners

    @Test func addPartner() {
        let m = makeModel()
        m.start()
        m.addPartner(named: "Jo")
        #expect(m.partners.count == 1)
        #expect(m.partners.first?.name == "Jo")
        #expect(m.performerOptions.map(\.name) == ["Me", "Jo"])
        #expect(m.performerLabel == "Me")
    }

    @Test func partnerRotation_afterLogSet() {
        let m = makeModel()
        m.start()
        m.addPartner(named: "Jo")
        m.addPartner(named: "Sam")
        let ex = try! WorkoutRepository.findOrCreateExercise(named: "TestPress", equipment: nil, in: context)
        m.startLogSet(for: ex)
        _ = m.logSet()
        #expect(m.currentPerformerIndex == 1)
        m.startLogSet(for: ex)
        _ = m.logSet()
        #expect(m.currentPerformerIndex == 2)
        m.startLogSet(for: ex)
        _ = m.logSet()
        #expect(m.currentPerformerIndex == 0)
    }

    @Test func partnerRotationShowsOnlyTheActiveLiftersSetsAndSetNumber() {
        let m = makeModel()
        m.start(initialPartnerNames: ["Jo", "Sam"], createSession: true)
        let ex = simpleExercise(named: "Partner History Press")
        m.startLogSet(for: ex)

        m.currentReps = 8
        _ = m.logSet() // Me -> Jo
        m.finishRest()
        #expect(m.performerLabel == "Jo")
        #expect(m.currentWorkoutHistoryLines == [])
        #expect(m.currentWorkingSetIndex == 1)

        m.currentReps = 10
        _ = m.logSet() // Jo -> Sam
        m.finishRest()
        #expect(m.performerLabel == "Sam")
        #expect(m.currentWorkoutHistoryLines == [])
        #expect(m.currentWorkingSetIndex == 1)

        m.currentReps = 12
        _ = m.logSet() // Sam -> Me
        m.finishRest()
        #expect(m.performerLabel == "Me")
        #expect(m.currentWorkoutHistoryLines.map(\.reps) == [8])
        #expect(m.currentWorkingSetIndex == 2)

        m.selectPerformer(at: 1)
        #expect(m.currentWorkoutHistoryLines.map(\.reps) == [10])
        #expect(m.currentWorkingSetIndex == 2)
        m.selectPerformer(at: 2)
        #expect(m.currentWorkoutHistoryLines.map(\.reps) == [12])
        #expect(m.currentWorkingSetIndex == 2)
    }

    @Test func priorWorkoutHistoryAlsoFollowsSelectedPartner() throws {
        let jo = try WorkoutRepository.findOrCreatePerson(named: "Jo", in: context)
        let ex = simpleExercise(named: "Prior Partner Press")
        let prior = try WorkoutRepository.createSession(title: "Prior", in: context)
        _ = try WorkoutRepository.addSet(to: prior, exercise: ex, weightKg: 70, reps: 8, in: context)
        _ = try WorkoutRepository.addSet(to: prior, exercise: ex, weightKg: 45, reps: 12,
                                         performedBy: jo, in: context)

        let m = makeModel()
        m.start(initialPartnerNames: ["Jo"], createSession: true)
        m.startLogSet(for: ex)
        #expect(m.previousWorkoutHistoryLines.map(\.reps) == [8])

        m.selectPerformer(at: 1)
        #expect(m.previousWorkoutHistoryLines.map(\.reps) == [12])
    }

    @Test func selectPerformer() {
        let m = makeModel()
        m.start()
        m.addPartner(named: "Jo")
        m.addPartner(named: "Sam")
        m.selectPerformer(at: 2)
        #expect(m.currentPerformerIndex == 2)
        #expect(m.performerLabel == "Sam")
        m.selectPerformer(at: 0)
        #expect(m.performerLabel == "Me")
    }

    @Test func removePartner() {
        let m = makeModel()
        m.start()
        m.addPartner(named: "Jo")
        m.addPartner(named: "Sam")
        m.removePartner(at: 0)
        #expect(m.partners.count == 1)
        #expect(m.partners.first?.name == "Sam")
    }

    @Test func partnerSet_excludedFromVolume() {
        let m = makeModel()
        m.start()
        m.addPartner(named: "Jo")
        m.addPartner(named: "Sam")
        let ex = try! WorkoutRepository.findOrCreateExercise(named: "TestPress", equipment: nil, in: context)
        m.currentWeight = 80; m.currentReps = 8
        m.startLogSet(for: ex); _ = m.logSet()
        m.startLogSet(for: ex); _ = m.logSet()
        m.startLogSet(for: ex); _ = m.logSet()
        #expect(m.setCount > 0)
    }

    // MARK: - Sync payloads

    @Test func logSetPayload_includesPerformedBy() {
        let m = makeModel()
        m.start()
        m.addPartner(named: "Jo")
        m.addPartner(named: "Sam")
        m.addPartner(named: "Max")
        let ex = try! WorkoutRepository.findOrCreateExercise(named: "TestPress", equipment: nil, in: context)
        m.startLogSet(for: ex)
        m.selectPerformer(at: 2)
        _ = m.logSet()
        #expect(m.lastPerformedByName == "Sam")
        #expect(m.lastSyncPayload?["performed_by_id"] != nil)
    }

    @Test func logSetPayload_includesSetId() {
        let m = makeModel()
        m.start()
        let ex = try! WorkoutRepository.findOrCreateExercise(named: "TestPress", equipment: nil, in: context)
        m.startLogSet(for: ex)
        _ = m.logSet()
        #expect(m.lastSyncPayload?["set_id"] != nil)
    }

    @Test func endSessionPayload() {
        let m = makeModel()
        m.start()
        let ex = try! WorkoutRepository.findOrCreateExercise(named: "TestPress", equipment: nil, in: context)
        m.startLogSet(for: ex)
        _ = m.logSet()
        m.finish()
        m.skipCooldown()
        let payload = m.endSessionPayload()
        #expect(payload != nil)
        #expect(payload?["action"] as? String == "end_session")
    }

    @Test func durationText() {
        let m = makeModel()
        m.start()
        let ex = try! WorkoutRepository.findOrCreateExercise(named: "TestPress", equipment: nil, in: context)
        m.startLogSet(for: ex)
        _ = m.logSet()
        let text = m.durationText
        #expect(!text.isEmpty)
    }

    // MARK: - Weight defaulting & display units

    private func poundsModel() -> WatchStrengthFlowModel {
        WatchStrengthFlowModel(context: context, unit: .pounds, cooldownDefault: 5, restDefault: 90)
    }

    /// Field regression: reopening the keypad must preserve a precise cable
    /// stack value instead of silently snapping it to a 2.5 lb boundary.
    @Test func startLogSet_pounds_preservesPreciseLastWeight() {
        let m = poundsModel()
        m.start()
        let ex = try! WorkoutRepository.findOrCreateExercise(named: "TestPress", equipment: nil, in: context)
        m.startLogSet(for: ex)
        m.currentWeightDisplay = 17.7
        _ = m.logSet()
        m.finishRest()
        m.startLogSet(for: ex)
        #expect(abs(m.currentWeightDisplay - 17.7) <= 0.001)
    }

    /// With no history, pounds still starts at the familiar empty-bar value.
    @Test func startLogSet_pounds_noHistoryDefaultsTo45() {
        let m = poundsModel()
        m.start()
        let ex = try! WorkoutRepository.findOrCreateExercise(named: "Fresh", equipment: nil, in: context)
        m.startLogSet(for: ex)
        #expect(abs(m.currentWeightDisplay - 45) <= 0.001)
    }

    /// The display accessor round-trips through canonical kg without drift.
    @Test func currentWeightDisplay_roundTripsPounds() {
        let m = poundsModel()
        m.currentWeightDisplay = 135
        #expect(abs(m.currentWeightDisplay - 135) <= 0.001)
        #expect(abs(m.currentWeight - WorkoutMath.canonical(135, from: .pounds)) <= 0.001)
    }

    /// Field regression: cable-stack loads must not be locked to 2.5 lb steps.
    @Test func crownIncrement_acceptsDecimalPounds() {
        let m = poundsModel()
        m.currentWeightDisplay = 100
        m.currentWeightDisplay += WeightIncrement(unit: .pounds).crownDetent
        #expect(abs(m.currentWeightDisplay - 100.1) <= 0.001)
        m.currentWeightDisplay = 17.7
        #expect(m.currentWeightText == "17.7")
    }

    @Test func previousSetHint() {
        let ex = try! WorkoutRepository.findOrCreateExercise(named: "TestPress", equipment: nil, in: context)
        let prior = try! WorkoutRepository.createSession(title: "Last",
                                                         date: Date(timeIntervalSince1970: 100),
                                                         in: context)
        _ = try! WorkoutRepository.addSet(to: prior, exercise: ex, weightKg: 100, reps: 8, in: context)

        let m = makeModel()
        m.start(createSession: true)
        m.startLogSet(for: ex)
        let hint = m.previousSetHint
        #expect(hint != nil)
        #expect(hint!.contains("Previous:"))
    }

    /// `lastPriorWorkingSet` now beats the rep-pattern ladder guess for a
    /// plan-less session (see `PerformerSetPlannerTests
    /// .testLastPriorWorkingSetBeatsRepPatternAndEstimatedLoadWithoutPlan` /
    /// `.testExtraSetBeyondPlanReturnsToHistory`): every set defaults to the
    /// exact last working set (70 kg x 8), not the historical ladder
    /// (12, 10, 8). The warmup set is still excluded from that pick.
    @Test func defaultRepsUseLastPriorWorkingSetIgnoringWarmups() {
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
        #expect(Int(m.currentReps) == 8)

        _ = m.logSet()
        m.finishRest()
        m.startLogSet(for: ex)
        #expect(Int(m.currentReps) == 8)
    }

    @Test func setHistoryLinesShowPriorAndCurrentWorkoutSets() {
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
        #expect(m.previousWorkoutHistoryLines.map(\.label) == ["W", "1", "2"])
        #expect(m.previousWorkoutHistoryLines.map(\.reps) == [6, 12, 10])

        m.currentWeight = 70
        m.currentReps = 12
        _ = m.logSet()
        m.finishRest()
        m.startLogSet(for: ex)
        #expect(m.currentWorkoutHistoryLines.map(\.label) == ["1"])
        #expect(m.currentWorkoutHistoryLines.map(\.reps) == [12])
        #expect(m.currentWorkingSetIndex == 2)
    }

    @Test func logSetPayloadIncludesPlannedSessionMetadata() {
        let m = makeModel()
        m.start(title: "Push Day",
                plannedExerciseNames: ["Bench Press"],
                repLadder: [12, 10, 8],
                planKey: "preset-push",
                createSession: true)

        let ex = m.exerciseList[0].exercise
        m.startLogSet(for: ex)
        _ = m.logSet()

        #expect(m.lastSyncPayload?["session_title"] as? String == "Push Day")
        #expect(m.lastSyncPayload?["planned_exercises"] as? [String] == ["Bench Press"])
        #expect(m.lastSyncPayload?["planned_rep_ladder"] as? [Int] == [12, 10, 8])
        #expect(m.lastSyncPayload?["plan_key"] as? String == "preset-push")
    }

    @Test func startCreateSessionLoadsInitialPartnersAndSessionRoster() {
        let m = makeModel()
        m.start(initialPartnerNames: ["Jo", "Sam", "Jo"], createSession: true)

        #expect(m.partners.map(\.name) == ["Jo", "Sam"])
        #expect(m.session?.activePartnerIDs.count == 2)
    }

    @Test func effortRPELogsToSetAndPayload() {
        let m = makeModel()
        m.start()
        let ex = simpleExercise(named: "Effort Press")
        m.startLogSet(for: ex)
        m.effortMode = .rpe
        m.effortValue = 8

        let set = m.logSet()

        #expect(set?.rpe == 8)
        #expect(m.lastSyncPayload?["rpe"] as? Double == 8)
        #expect(m.lastSyncPayload?["effort_mode"] as? String == "rpe")
    }

    @Test func effortRIRConvertsToStoredRPE() {
        let m = makeModel()
        m.start()
        let ex = simpleExercise(named: "RIR Press")
        m.startLogSet(for: ex)
        m.effortMode = .rir
        m.effortValue = 2

        let set = m.logSet()

        #expect(set?.rpe == 8)
        #expect(m.lastSyncPayload?["effort_mode"] as? String == "rir")
        #expect(m.lastSyncPayload?["effort_value"] as? Double == 2)
    }

    @Test func logLastSetRestsThenAdvancesToNextExercise() {
        let m = makeModel()
        m.start()
        let first = simpleExercise(named: "Last Set Press")
        let second = simpleExercise(named: "Next Up Row")
        m.startLogSet(for: second)
        _ = m.logSet()
        m.finishRest()
        m.startLogSet(for: first)
        _ = m.logLastSet()
        #expect(m.stage == .rest)
        m.finishRest()
        #expect(m.stage != .keypad(first))
    }

    @Test func logLastSetWithNoNextExerciseRestsThenHome() {
        let m = makeModel()
        m.start()
        let ex = simpleExercise(named: "Last Set Press")
        m.startLogSet(for: ex)

        _ = m.logLastSet()

        #expect(m.stage == .rest)
        m.finishRest()
        #expect(m.stage == .home)
        #expect(m.exerciseList.first?.setCount == 1)
        #expect(m.allExercisesCompletePrompt)
    }

    // MARK: - Exercise-wide partner completion (#444)

    /// Starts a session with partners and explicit working-set counts per lifter
    /// (index 0 = Me). Returns the model and the planned exercises.
    private func plannedPartnerModel(counts: [Int], exercises names: [String] = ["Shared Press"])
        -> (WatchStrengthFlowModel, [Exercise]) {
        let m = makeModel()
        m.start(createSession: true)
        for i in 1..<counts.count { m.addPartner(named: "Partner \(i)") }
        let exs = names.map { simpleExercise(named: $0) }
        let sets = { (n: Int) in (0..<n).map { _ in PlannedSetPrescription(targetReps: 5, targetWeightKg: 60) } }
        let ids = [nil] + m.partners.map { Optional($0.id.uuidString) }
        m.session?.plannedPerformerPrescriptions = counts.enumerated().map { index, n in
            PlannedPerformerPrescription(
                performerID: ids[index],
                exercises: names.map { PlannedExercisePrescription(exerciseName: $0, sets: sets(n)) })
        }
        m.session?.plannedExerciseNames = names
        m.refreshExerciseList()
        return (m, exs)
    }

    /// Logs one set via the normal button and returns the performer index who logged it.
    @discardableResult
    private func logNormal(_ m: WatchStrengthFlowModel, _ ex: Exercise) -> Int {
        m.startLogSet(for: ex)
        let who = m.currentPerformerIndex
        #expect(m.logSet() != nil)
        #expect(m.stage == .rest)
        return who
    }

    @Test func twoLiftersThreeSets_allSixTurnsInOrder_thenCompletes() {
        let (m, exs) = plannedPartnerModel(counts: [3, 3])
        let ex = exs[0]
        var order: [Int] = []
        for _ in 0..<6 {
            if case .keypad = m.stage {} else { m.startLogSet(for: ex) }
            order.append(logNormal(m, ex))
            if order.count < 6 {
                #expect(m.exercisePendingAfterRest?.id == ex.id)
                #expect(m.currentPerformerIndex == order.count % 2)
                m.finishRest()
                #expect(m.stage == .keypad(ex))
            }
        }
        #expect(order == [0, 1, 0, 1, 0, 1])
        #expect(m.exercisePendingAfterRest == nil)
        m.finishRest()
        #expect(m.stage == .home)
    }

    @Test func meFinalSetDoesNotLeaveWhilePartnerOutstanding() {
        let (m, exs) = plannedPartnerModel(counts: [3, 3])
        for _ in 0..<5 { logNormal(m, exs[0]); m.finishRest() }
        // Me3 was the fifth turn.
        #expect(m.currentPerformerIndex == 1)
        #expect(m.stage == .keypad(exs[0]))
        #expect(m.setCardState?.lifterText == "Partner 1")
    }

    @Test func completedExerciseRoutesToNextPlannedExercise() {
        let (m, exs) = plannedPartnerModel(counts: [1, 1], exercises: ["Shared Press", "Shared Row"])
        logNormal(m, exs[0]); m.finishRest()
        logNormal(m, exs[0])
        #expect(m.exercisePendingAfterRest?.id == exs[1].id)
        m.finishRest()
        #expect(m.stage == .keypad(exs[1]))
        #expect(m.currentPerformerIndex == 0)
    }

    @Test func unequalPlans_meThreePartnerTwo() {
        let (m, exs) = plannedPartnerModel(counts: [3, 2])
        var order: [Int] = []
        for _ in 0..<5 {
            if case .keypad = m.stage {} else { m.startLogSet(for: exs[0]) }
            order.append(logNormal(m, exs[0]))
            if order.count < 5 { #expect(m.exercisePendingAfterRest?.id == exs[0].id); m.finishRest() }
        }
        #expect(order == [0, 1, 0, 1, 0])
        #expect(m.exercisePendingAfterRest == nil)
    }

    @Test func threeLifters_unequalCounts_noOneRepeatsWhileOthersPending() {
        let (m, exs) = plannedPartnerModel(counts: [3, 2, 1])
        var order: [Int] = []
        for _ in 0..<6 {
            if case .keypad = m.stage {} else { m.startLogSet(for: exs[0]) }
            order.append(logNormal(m, exs[0]))
            if order.count < 6 { #expect(m.exercisePendingAfterRest?.id == exs[0].id); m.finishRest() }
        }
        #expect(order == [0, 1, 2, 0, 1, 0])
        #expect(m.exercisePendingAfterRest == nil)
    }

    @Test func singleLifterFinalPlannedSetMovesOn() {
        let (m, exs) = plannedPartnerModel(counts: [1], exercises: ["Solo Press", "Solo Row"])
        logNormal(m, exs[0])
        #expect(m.exercisePendingAfterRest?.id == exs[1].id)
    }

    @Test func adHocExerciseKeepsRoundRobinWithoutManufacturingObligations() {
        let m = makeModel()
        m.start(createSession: true)
        m.addPartner(named: "Pat")
        let ex = simpleExercise(named: "Ad Hoc Curl")
        logNormal(m, ex)
        #expect(m.exercisePendingAfterRest?.id == ex.id)
        #expect(m.currentPerformerIndex == 1)
        m.finishRest()
        #expect(!m.hasOutstandingWorkingSet(for: ex, performerIndex: 1))
    }

    @Test func setCardNextLifterSkipsCompleted() {
        let (m, exs) = plannedPartnerModel(counts: [2, 1, 2])
        for _ in 0..<3 { logNormal(m, exs[0]); m.finishRest() }   // Me1, P1, P2(1)
        // Selected: Me (2nd set, last for Me); Partner 1 is complete, Partner 2 remains.
        #expect(m.currentPerformerIndex == 0)
        let card = m.setCardState
        #expect(card?.lifterText == "Me · then Partner 2")
        #expect(card?.logTitle == "Log set", "the primary action always reads \"Log set\"")
    }

    @Test func manualSelectionDoesNotOrphanPlannedPerformer() {
        let (m, exs) = plannedPartnerModel(counts: [2, 2])
        m.selectPerformer(at: 1)
        logNormal(m, exs[0]); m.finishRest()      // Partner 1 set 1 → Me
        #expect(m.currentPerformerIndex == 0)
        logNormal(m, exs[0]); m.finishRest()      // Me 1 → Partner 1
        logNormal(m, exs[0]); m.finishRest()      // Partner 1 set 2 (done) → Me
        #expect(m.currentPerformerIndex == 0)
        logNormal(m, exs[0])                      // Me 2
        #expect(m.exercisePendingAfterRest == nil)  // every planned turn is done
        #expect(!m.performerIndices.contains { m.hasOutstandingWorkingSet(for: exs[0], performerIndex: $0) })
    }

    @Test func logAsLastSetDoesNotAbandonOutstandingPartner() {
        let (m, exs) = plannedPartnerModel(counts: [2, 2])
        m.startLogSet(for: exs[0])
        #expect(m.logLastSet() != nil)
        #expect(m.exercisePendingAfterRest?.id == exs[0].id)
        #expect(m.currentPerformerIndex == 1)
    }

    @Test func deleteSetRemovesLocalSetAndEmitsPayload() {
        let m = makeModel()
        m.start()
        let ex = simpleExercise(named: "Delete Set Press")
        m.startLogSet(for: ex)
        let set = m.logSet()
        m.finishRest()
        m.startLogSet(for: ex)

        let payload = m.deleteSet(id: set!.id)

        #expect(m.currentWorkoutHistoryLines.count == 0)
        #expect(payload?["action"] as? String == "delete_set")
        #expect(payload?["set_id"] as? String == set?.id.uuidString)
    }

    @Test func deleteSetAllowsReentryDuringSameExercise() {
        let m = makeModel()
        m.start()
        let ex = simpleExercise(named: "Reenter Set Press")
        m.startLogSet(for: ex)
        let first = m.logSet()
        m.finishRest()

        #expect(m.deleteSet(id: first!.id) != nil)
        #expect(m.currentWorkoutHistoryLines == [])

        m.currentWeight = 75
        m.currentReps = 6
        let replacement = m.logLastSet()

        #expect(replacement != nil)
        #expect(m.session?.orderedSets.count == 1)
        #expect(m.session?.orderedSets.first?.reps == 6)
        #expect(m.stage == .rest)
    }

    @Test func deleteExerciseRemovesPlannedNameSetsAndEmitsPayload() {
        let m = makeModel()
        m.start(createSession: true)
        let ex = simpleExercise(named: "Delete Exercise Press")
        m.addExercise(named: ex.name)
        m.startLogSet(for: ex)
        _ = m.logSet()

        let payload = m.deleteExercise(ex)

        #expect(m.exerciseList.isEmpty)
        #expect(m.session?.orderedSets.isEmpty == true)
        #expect(payload?["action"] as? String == "delete_exercise")
        #expect(payload?["exercise"] as? String == ex.name)
    }

    @Test func endSessionPayloadIncludesMetadataForOutOfOrderPhoneFinalize() {
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

        #expect(payload?["session_title"] as? String == "Push Day")
        #expect(payload?["planned_exercises"] as? [String] == ["Bench Press"])
        #expect(payload?["planned_rep_ladder"] as? [Int] == [12, 10, 8])
        #expect(payload?["plan_key"] as? String == "preset-push")
        #expect(payload?["ended_at"] != nil)
    }

    @Test func directSummaryHeartRateSnapshotIsKeptAndIdempotent() throws {
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
        let payload = try #require(m.endSessionPayload())
        #expect(payload[WatchStrengthHeartRate.transportKey] != nil)
        #expect(m.recordedHeartRate == dense)
    }

    @Test func legacyPayloadHasSourceButNoInventedFinalSequence() throws {
        let m = makeModel()
        m.start(title: "Push", plannedExerciseNames: ["Bench Press"], createSession: true)
        let dense = (0..<5).map { HRSamplePoint(t: Double($0) * 5, bpm: 110 + Double($0)) }
        m.recordHeartRate(dense)
        let legacy = try #require(m.endSessionPayload())
        #expect(legacy["hr_final_sequence"] == nil)
        #expect(legacy["hr_source"] as? String == HeartRateSource.watchHealthKit.rawValue)
        #expect(legacy["hr_captured_at"] != nil)
        let durable = try #require(m.endSessionPayload(finalSequence: 2))
        #expect(durable["hr_final_sequence"] as? Int == 2)
        #expect(durable["hr_sample_count"] as? Int != 2)
    }

    // MARK: - Synced owner history defaults

    private struct StubHistory: WatchSetDefaultHistoryProviding {
        var snapshot: WatchSetDefaultSnapshot
        func history(exerciseKey: String, performerID: String, performerName: String?) -> PerformerSetPlanner.History {
            snapshot.history(exerciseKey: exerciseKey, performerID: performerID, performerName: performerName)
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

    @Test func syncedOwnerSnapshotPrefillsFirstSetAndMatchesDirectResolver() {
        let snap = benchSnapshot()
        let m = syncedModel(snapshot: snap)
        let ex = m.exerciseList[0].exercise
        m.startLogSet(for: ex)
        let direct = PerformerSetPlanner.resolve(
            setIndex: 0, performerPlan: nil, ownerPlan: [], ownerLadder: nil, isOwner: true,
            history: snap.history(exerciseKey: "Bench Press", performerID: "owner"))
        #expect(m.currentWeight == 125)
        #expect(m.currentReps == 8)
        #expect(m.currentWeight == direct.weightKg)
        #expect(m.currentReps == Double(direct.reps))
    }

    @Test func justLoggedWatchSetOverridesSnapshot() {
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
        #expect(m.currentWeight == 130)
        #expect(m.currentReps == 6)
    }

    @Test func explicitPlanOverridesSnapshot() {
        let plan = WatchPlanPayload(strength: .init(
            exerciseNames: ["Bench Press"],
            prescriptions: [PlannedExercisePrescription(
                exerciseName: "Bench Press",
                sets: [PlannedSetPrescription(targetReps: 6, targetWeightKg: 135)])]))
        let m = syncedModel(plan: plan, snapshot: benchSnapshot())
        m.startLogSet(for: m.exerciseList[0].exercise)
        #expect(m.currentWeight == 135)
        #expect(m.currentReps == 6)
    }

    @Test func noSnapshotOrNoHistoryKeepsFallbacks() {
        let m = syncedModel()
        m.startLogSet(for: m.exerciseList[0].exercise)
        #expect(m.currentWeight == 20)
        let empty = syncedModel(snapshot: WatchSetDefaultSnapshot(generatedAt: Date(), performers: []))
        empty.startLogSet(for: empty.exerciseList[0].exercise)
        #expect(empty.currentWeight == m.currentWeight)
        #expect(empty.currentReps == m.currentReps)
    }
    // MARK: - Completion attribution (all end paths)

    @MainActor
    private func completionOutbox() -> WatchStrengthCompletionOutbox {
        let store = FakeHRStore(), transport = FakeHRTransport()
        transport.store = store
        return WatchStrengthCompletionOutbox(outbox: WatchHeartRateOutbox(
            store: store, transport: transport, clock: { 1_800_000_100 }))
    }

    @MainActor
    private func loggedModel() -> WatchStrengthFlowModel {
        let m = makeModel()
        m.start()
        m.addExercise(named: "Bench Press")
        m.startLogSet(for: m.exerciseList[0].exercise)
        m.currentWeight = 80; m.currentReps = 5
        _ = m.logSet()
        return m
    }

    private var hrProfile: CardioIntensityProfile {
        CardioIntensityProfile(restingHR: 60, maximumHR: 180, maximumHRSource: .userEntered)
    }

    @MainActor
    private func assertCoordinatorPath(_ end: (WatchStrengthFlowModel) -> Void) throws {
        let m = loggedModel()
        let samples = (0..<20).map { HRSamplePoint(t: Double($0) * 15, bpm: 140) }
        end(m)
        var recorded: [WatchWeekLocalOverlay] = []
        var sent = 0
        let result = WatchStrengthCompletionCoordinator.complete(
            model: m, samples: samples, profile: hrProfile, outbox: completionOutbox(),
            weekKey: { _ in "wk" },
            recordOverlay: { recorded.append($0); #expect(sent == 0, "overlay before transfer") },
            send: { _ in sent += 1 })
        let attribution = try #require(result)
        #expect(sent == 1)
        #expect(m.recordedHeartRate == samples)
        #expect(attribution.hrSamples == samples)
        #expect(recorded.count == 1)
        #expect(recorded[0].id.uuidString == m.session?.completionID)
        #expect(recorded[0].sets == Double(m.session?.completedOwnerWorkingSetCount ?? -1))
        #expect(recorded[0].sets == 1)
        #expect(recorded[0].completedAt == m.session?.endedAt)
        #expect(recorded[0].moderateEquivalentMinutes > 0)
        #expect(attribution.cardioSummary ==
                       CardioMinuteAccumulator.summarize(duration: m.durationSeconds, samples: samples, profile: hrProfile))
        // Retry keeps the same completion identity (store replaces by ID).
        let again = WatchStrengthCompletionCoordinator.complete(
            model: m, samples: samples, profile: hrProfile, outbox: completionOutbox(),
            weekKey: { _ in "wk" }, recordOverlay: { recorded.append($0) }, send: { _ in })
        #expect(again?.overlay.id == recorded[0].id)
    }

    @MainActor
    @Test func completionCoordinator_cooldownCompletionPath() throws {
        try assertCoordinatorPath { $0.completeCooldown() }
    }

    @MainActor
    @Test func completionCoordinator_zeroCooldownDirectSummaryPath() throws {
        try assertCoordinatorPath { $0.skipCooldown() }
    }

    @MainActor
    @Test func completionCoordinator_inactivityResumedSessionPath() throws {
        try assertCoordinatorPath { m in
            // Inactivity finalization resumes a persisted session in a fresh model.
            let session = m.session!
            session.endedAt = Date()
            try? context.save()
            m.start(resuming: session)
        }
    }

    @MainActor
    @Test func completionCoordinator_noSamplesCreditsSetsOnly() throws {
        let m = loggedModel()
        m.skipCooldown()
        var recorded: [WatchWeekLocalOverlay] = []
        WatchStrengthCompletionCoordinator.complete(
            model: m, samples: [], profile: hrProfile, outbox: completionOutbox(),
            weekKey: { _ in "wk" }, recordOverlay: { recorded.append($0) }, send: { _ in })
        #expect(recorded.first?.sets == 1)
        #expect(recorded.first?.moderateEquivalentMinutes == 0)
    }
}

struct WatchAddConfirmationTests {
    private let target = WatchAddConfirmation.Target(id: UUID(), name: "Bench Press")

    @Test func requestAndCancelNeverCallAdd() {
        var state = WatchAddConfirmation()
        state.request(target)
        #expect(state.pending == target)
        state.cancel()
        var calls = 0
        #expect(state.confirm { _, _ in calls += 1; return .added(name: "x") } == nil)
        #expect(calls == 0)
        #expect(state.pending == nil)
        #expect(state.outcome == nil)
    }

    @Test func confirmCallsAddOnceAndRecordsOutcomes() {
        var state = WatchAddConfirmation()
        var calls = 0
        state.request(target)
        var confirmedID: UUID?
        #expect(state.confirm { id, name in calls += 1; confirmedID = id; return .added(name: name) } ==
                       .added(name: "Bench Press"))
        #expect(confirmedID == self.target.id)
        #expect(calls == 1)
        #expect(state.outcome == nil)

        state.request(target)
        state.confirm { _, name in .alreadyPresent(name: name) }
        #expect(state.outcome == .alreadyPresent(name: "Bench Press"))
        state.request(target)
        state.confirm { _, name in .unavailable(name: name) }
        #expect(state.outcome == .unavailable(target))
    }

    @Test func retryReopensConfirmationWithoutMutating() {
        var state = WatchAddConfirmation()
        var calls = 0
        state.request(target)
        state.confirm { _, name in calls += 1; return .saveFailed(name: name) }
        #expect(state.outcome == .saveFailed(target))
        state.retry()
        #expect(calls == 1)
        #expect(state.pending == target)
        #expect(state.outcome == nil)
        state.cancel()
        #expect(state.confirm { _, name in calls += 1; return .added(name: name) } == nil)
        #expect(calls == 1)
    }

    @Test func retryIgnoredForUnavailable() {
        var state = WatchAddConfirmation()
        state.request(target)
        state.confirm { _, name in .unavailable(name: name) }
        state.retry()
        #expect(state.pending == nil)
    }
}
#endif
