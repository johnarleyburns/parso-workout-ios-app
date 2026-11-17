import XCTest
import SwiftData
@testable import CadenceFeatures
import CadenceCore

/// Watch redesign (plans/watch-redesign/2026-09-30/DESIGN.md §7): the Set Card, Today hero,
/// receipts, cardio tile order, Quick Talk planner and the TodayPlan advice round trip.
final class WatchRedesignTests: XCTestCase {

    // MARK: - Set Card

    func testRingUsesTheExerciseListProgressPolicy() {
        let state = card(current: 100, reps: 5, prefill: 100, prefillReps: 5)
        XCTAssertEqual(state.exerciseProgress.exerciseName, state.exerciseName)
        XCTAssertEqual(state.exerciseProgress.completedSetCount, 0)
        XCTAssertEqual(state.exerciseProgress.exerciseNameMaxLines, 2)
    }

    func testLogTitleAlwaysReadsLogSetEvenWhenTheSetEchoesAChange() {
        let unchanged = card(current: 100, reps: 5, prefill: 100, prefillReps: 5)
        XCTAssertFalse(unchanged.echoesChange)
        XCTAssertEqual(unchanged.logTitle, "Log set")
        let changed = card(current: 100, reps: 4, prefill: 100, prefillReps: 5)
        XCTAssertTrue(changed.echoesChange)
        XCTAssertEqual(changed.logTitle, "Log set", "field report: an echoing title made the button feel unstable")
    }

    func testPlanLineCitesOnlyRealScienceClaims() {
        let rpe = WatchSetCardBuilder.planLine(
            planned: PlannedSetPrescription(targetReps: 5, targetWeightKg: 100, targetRPE: 8),
            prefillWeightKg: 100, lastTime: nil, unit: .kilograms, isWarmup: false)
        XCTAssertEqual(rpe?.citationIDs, ["rpeAutoregulation"])

        let percent = WatchSetCardBuilder.planLine(
            planned: PlannedSetPrescription(targetReps: 5, targetWeightKg: 100, oneRepMaxPercent: 0.75),
            prefillWeightKg: 100, lastTime: nil, unit: .kilograms, isWarmup: false)
        XCTAssertEqual(percent?.citationIDs, ["oneRMEstimation"])
        XCTAssertTrue(percent?.text.contains("75") ?? false)

        let fact = WatchSetCardBuilder.planLine(
            planned: PlannedSetPrescription(targetReps: 5, targetWeightKg: 102.5),
            prefillWeightKg: 102.5, lastTime: .init(weightKg: 100, reps: 5, rpe: 8),
            unit: .kilograms, isWarmup: false)
        XCTAssertEqual(fact?.citationIDs, [], "a plan fact makes no science claim")
        XCTAssertTrue(fact?.text.contains("+2.5") ?? false)

        let userChanged = WatchSetCardBuilder.planLine(
            planned: PlannedSetPrescription(targetReps: 5, targetWeightKg: 102.5),
            prefillWeightKg: 97.5, lastTime: .init(weightKg: 100, reps: 5, rpe: nil),
            unit: .kilograms, isWarmup: false)
        XCTAssertNil(userChanged, "no plan line when the prefill didn't come from the plan")
    }

    func testEveryWatchCitationResolves() {
        let ids = ["rpeAutoregulation", "oneRMEstimation"] + WatchSync.TodayPlan.Session.adviceCitations
        for id in ids {
            XCTAssertNotNil(CitationRegistry.citation(forId: id), "\(id) must resolve (HARD RULE)")
        }
    }

    func testModelTracksPrefillPlannedRestAndPR() throws {
        let container = try CadenceStore.makeModelContainer(inMemory: true)
        let context = ModelContext(container)
        _ = try WorkoutRepository.seedStarterLibraryIfNeeded(context)
        let model = WatchStrengthFlowModel(context: context, unit: .kilograms, cooldownDefault: 5, restDefault: 30)
        let plan = WatchPlanPayload(strength: .init(
            exerciseNames: ["Bench Press"],
            prescriptions: [PlannedExercisePrescription(exerciseName: "Bench Press", sets: [
                PlannedSetPrescription(targetReps: 5, targetWeightKg: 60, restSeconds: 150),
                PlannedSetPrescription(targetReps: 5, targetWeightKg: 60, restSeconds: 150)
            ])]))
        model.start(title: "Push", plannedExerciseNames: ["Bench Press"], planPayload: plan, createSession: true)
        let exercise = try XCTUnwrap(model.exerciseList.first?.exercise)
        model.startLogSet(for: exercise)

        let state = try XCTUnwrap(model.setCardState)
        XCTAssertEqual(state.exerciseProgress.completedSetCount, 0)
        XCTAssertEqual(state.exerciseProgress.plannedSetCount, 2)
        XCTAssertEqual(state.exerciseProgress.progress, 0)
        XCTAssertEqual(model.prefillReps, 5)
        XCTAssertFalse(state.echoesChange)

        model.currentReps = 4
        XCTAssertTrue(try XCTUnwrap(model.setCardState).echoesChange)

        _ = model.logSet()
        XCTAssertFalse(model.plannedRestApplied)
        XCTAssertEqual(model.restTimer.remaining, 30, "the user's default rest wins over plan rest (issue #49)")
        XCTAssertTrue(model.lastLoggedSetWasPR, "a first-ever working set is a PR")
    }

    func testEffortChipCycles() throws {
        let container = try CadenceStore.makeModelContainer(inMemory: true)
        let model = WatchStrengthFlowModel(context: ModelContext(container))
        XCTAssertNil(model.effortValue)
        model.cycleEffort(); XCTAssertEqual(model.effortValue, 6)
        model.effortValue = 10
        model.cycleEffort(); XCTAssertNil(model.effortValue)
    }

    // MARK: - Today hero

    func testResumeWinsAndDescribesWhereYouWere() {
        let resume = WatchTodayHeroBuilder.ResumeInput(
            title: "Push A", startedAt: Date(timeIntervalSince1970: 0),
            exercises: [("Bench", 4), ("OHP", 2)], plannedSets: ["ohp": 4])
        guard case .resume(_, let detail, _) = WatchTodayHeroBuilder.make(resume: resume, plan: nil) else {
            return XCTFail("resume must lead")
        }
        XCTAssertTrue(detail.contains("Bench"))
        XCTAssertTrue(detail.contains("2"))
        XCTAssertTrue(detail.contains("4"))
    }

    func testSyncedEmptyTodayPlanDoesNotAskToOpenThePhoneAgain() {
        XCTAssertEqual(
            WatchTodayHeroBuilder.make(resume: nil, plan: nil, synced: true),
            .unplanned(synced: true))
        XCTAssertEqual(
            WatchTodayHeroBuilder.make(resume: nil, plan: nil, synced: false),
            .unplanned(synced: false))
    }

    func testPlannedStrengthEstimatesMinutesOnlyFromKnownSets() {
        let withSets = WatchSync.TodayPlan(sessions: [
            .init(id: "s", kind: .strength, label: "Push A", exerciseNames: ["Bench"],
                  planPayload: WatchPlanPayload(strength: .init(prescriptions: [
                      PlannedExercisePrescription(exerciseName: "Bench", sets: Array(repeating:
                        PlannedSetPrescription(targetReps: 5), count: 6))])))
        ])
        guard case .planned(_, _, _, let minutes, _) = WatchTodayHeroBuilder.make(resume: nil, plan: withSets) else {
            return XCTFail("planned strength expected")
        }
        XCTAssertEqual(minutes, 13)

        let unknown = WatchSync.TodayPlan(sessions: [.init(id: "s", kind: .strength, label: "Push", exerciseNames: ["Bench"])])
        guard case .planned(_, _, _, let none, _) = WatchTodayHeroBuilder.make(resume: nil, plan: unknown) else {
            return XCTFail("planned strength expected")
        }
        XCTAssertNil(none, "never guess a duration")
    }

    func testRestDayCarriesTheCoachNoteWithCitations() {
        let plan = WatchSync.TodayPlan(sessions: [
            .init(id: "r", kind: .rest, label: "Rest", adviceNote: "Readiness is low — consider keeping today lighter.",
                  adviceCitationIDs: WatchSync.TodayPlan.Session.adviceCitations)
        ])
        guard case .restDay(let advice) = WatchTodayHeroBuilder.make(resume: nil, plan: plan) else {
            return XCTFail("rest day expected")
        }
        XCTAssertEqual(advice?.citationIDs, WatchSync.TodayPlan.Session.adviceCitations)
    }

    func testTodayPlanAdviceRoundTripsThroughTheContext() {
        let plan = WatchSync.TodayPlan(sessions: [
            .init(id: "s", kind: .strength, label: "Legs", adviceNote: "Consider a lighter session — 6 hard days in a row.",
                  adviceCitationIDs: ["meeusenOvertraining2013"])
        ])
        let decoded = WatchSync.TodayPlan.from(context: WatchSync.TodayPlan.contextDict(plan))
        XCTAssertEqual(decoded?.sessions.first?.adviceNote, plan.sessions[0].adviceNote)
        XCTAssertEqual(decoded?.sessions.first?.adviceCitationIDs, ["meeusenOvertraining2013"])
    }

    // MARK: - Receipts and cardio order

    func testReceiptsSayWhereEachCopyIs() {
        let sending = WatchSaveReceipt.make(savedOnWatch: true, pendingTransfers: 3, phoneReachable: true, transferError: nil)
        XCTAssertEqual(sending.watch, .done)
        guard case .inProgress = sending.iPhone else { return XCTFail("sending expected") }
        guard case .waiting = sending.health else { return XCTFail("health waits for the phone") }

        let away = WatchSaveReceipt.make(savedOnWatch: true, pendingTransfers: 3, phoneReachable: false, transferError: nil)
        guard case .waiting = away.iPhone else { return XCTFail("waiting expected") }

        let done = WatchSaveReceipt.make(savedOnWatch: true, pendingTransfers: 0, phoneReachable: false, transferError: nil)
        XCTAssertEqual(done.iPhone, .done)
        XCTAssertEqual(done.health, .done)

        let failed = WatchSaveReceipt.make(savedOnWatch: true, pendingTransfers: 1, phoneReachable: true, transferError: "x")
        XCTAssertEqual(failed.iPhone, .failed("x"))
    }

    func testCardioTilesLearnTheOrder() {
        let order = WatchCardioTileOrder.ordered(["run", "cycle", "boxing", "hiit", "row", "swim"],
                                                 counts: ["swim": 9, "row": 4, "run": 4])
        XCTAssertEqual(order.tiles, ["swim", "run", "row", "cycle"])
        XCTAssertEqual(order.more, ["boxing", "hiit"])
    }

    // MARK: - Helpers

    private func card(current: Double, reps: Int, prefill: Double, prefillReps: Int) -> WatchSetCardState {
        WatchSetCardBuilder.make(exerciseName: "Bench", plannedWorkingSets: [], completedWorkingSets: 0,
                                 currentWeightKg: current, currentReps: reps, prefillWeightKg: prefill,
                                 prefillReps: prefillReps, lastTime: nil, unit: .kilograms, lifter: nil,
                                 nextLifter: nil, effortText: nil, isWarmup: false)
    }
}

/// Watch redesign §5 I1–I2 — interval phase tone and the steady-cardio plan target.
final class WatchCardioRedesignTests: XCTestCase {
    func testIntervalToneIsWorkRestEndingOrEasy() {
        XCTAssertEqual(WatchIntervalPhaseTone.tone(for: .work), .work)
        XCTAssertEqual(WatchIntervalPhaseTone.tone(for: .warning), .ending)
        XCTAssertEqual(WatchIntervalPhaseTone.tone(for: .imminent), .ending)
        XCTAssertEqual(WatchIntervalPhaseTone.tone(for: .rest), .rest)
        XCTAssertEqual(WatchIntervalPhaseTone.tone(for: .neutral), .easy)
    }

    func testPlanTargetShowsOnlyWhatWasPlanned() {
        XCTAssertNil(WatchCardioPlanTarget.text(durationSeconds: nil, zone: nil))
        XCTAssertNil(WatchCardioPlanTarget.text(durationSeconds: 0, zone: 9))
        XCTAssertEqual(WatchCardioPlanTarget.text(durationSeconds: 1800, zone: 2), "Planned: 30 min · Zone 2")
        XCTAssertEqual(WatchCardioPlanTarget.text(durationSeconds: nil, zone: 3), "Planned: Zone 3")
        XCTAssertEqual(WatchCardioPlanTarget.progress(elapsed: 900, durationSeconds: 1800), 0.5)
        XCTAssertEqual(WatchCardioPlanTarget.progress(elapsed: 4000, durationSeconds: 1800), 1)
        XCTAssertNil(WatchCardioPlanTarget.progress(elapsed: 10, durationSeconds: nil))
    }
}
