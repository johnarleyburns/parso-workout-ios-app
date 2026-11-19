#if canImport(SwiftData)
import Foundation
import Testing
import SwiftData
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures
import CadenceCore
import CadencePhoneFeatures

/// Watch redesign (plans/watch-redesign/2026-09-30/DESIGN.md §7): the Set Card, Today hero,
/// receipts, cardio tile order, Quick Talk planner and the TodayPlan advice round trip.
struct WatchRedesignTests {

    // MARK: - Set Card

    @Test func ringUsesTheExerciseListProgressPolicy() {
        let state = card(current: 100, reps: 5, prefill: 100, prefillReps: 5)
        #expect(state.exerciseProgress.exerciseName == state.exerciseName)
        #expect(state.exerciseProgress.completedSetCount == 0)
        #expect(state.exerciseProgress.exerciseNameMaxLines == 2)
    }

    @Test func logTitleAlwaysReadsLogSetEvenWhenTheSetEchoesAChange() {
        let unchanged = card(current: 100, reps: 5, prefill: 100, prefillReps: 5)
        #expect(!unchanged.echoesChange)
        #expect(unchanged.logTitle == "Log set")
        let changed = card(current: 100, reps: 4, prefill: 100, prefillReps: 5)
        #expect(changed.echoesChange)
        #expect(changed.logTitle == "Log set", "field report: an echoing title made the button feel unstable")
    }

    @Test func planLineCitesOnlyRealScienceClaims() {
        let rpe = WatchSetCardBuilder.planLine(
            planned: PlannedSetPrescription(targetReps: 5, targetWeightKg: 100, targetRPE: 8),
            prefillWeightKg: 100, lastTime: nil, unit: .kilograms, isWarmup: false)
        #expect(rpe?.citationIDs == ["rpeAutoregulation"])

        let percent = WatchSetCardBuilder.planLine(
            planned: PlannedSetPrescription(targetReps: 5, targetWeightKg: 100, oneRepMaxPercent: 0.75),
            prefillWeightKg: 100, lastTime: nil, unit: .kilograms, isWarmup: false)
        #expect(percent?.citationIDs == ["oneRMEstimation"])
        #expect(percent?.text.contains("75") ?? false)

        let fact = WatchSetCardBuilder.planLine(
            planned: PlannedSetPrescription(targetReps: 5, targetWeightKg: 102.5),
            prefillWeightKg: 102.5, lastTime: .init(weightKg: 100, reps: 5, rpe: 8),
            unit: .kilograms, isWarmup: false)
        #expect(fact?.citationIDs == [], "a plan fact makes no science claim")
        #expect(fact?.text.contains("+2.5") ?? false)

        let userChanged = WatchSetCardBuilder.planLine(
            planned: PlannedSetPrescription(targetReps: 5, targetWeightKg: 102.5),
            prefillWeightKg: 97.5, lastTime: .init(weightKg: 100, reps: 5, rpe: nil),
            unit: .kilograms, isWarmup: false)
        #expect(userChanged == nil, "no plan line when the prefill didn't come from the plan")
    }

    @Test func everyWatchCitationResolves() {
        let ids = ["rpeAutoregulation", "oneRMEstimation"] + WatchSync.TodayPlan.Session.adviceCitations
        for id in ids {
            #expect(CitationRegistry.citation(forId: id) != nil, "\(id) must resolve (HARD RULE)")
        }
    }

    @Test func modelTracksPrefillPlannedRestAndPR() throws {
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
        let exercise = try #require(model.exerciseList.first?.exercise)
        model.startLogSet(for: exercise)

        let state = try #require(model.setCardState)
        #expect(state.exerciseProgress.completedSetCount == 0)
        #expect(state.exerciseProgress.plannedSetCount == 2)
        #expect(state.exerciseProgress.progress == 0)
        #expect(model.prefillReps == 5)
        #expect(!state.echoesChange)

        model.currentReps = 4
        #expect(try #require(model.setCardState).echoesChange)

        _ = model.logSet()
        #expect(!model.plannedRestApplied)
        #expect(model.restTimer.remaining == 30, "the user's default rest wins over plan rest (issue #49)")
        #expect(model.lastLoggedSetWasPR, "a first-ever working set is a PR")
    }

    @Test func effortChipCycles() throws {
        let container = try CadenceStore.makeModelContainer(inMemory: true)
        let model = WatchStrengthFlowModel(context: ModelContext(container))
        #expect(model.effortValue == nil)
        model.cycleEffort(); #expect(model.effortValue == 6)
        model.effortValue = 10
        model.cycleEffort(); #expect(model.effortValue == nil)
    }

    // MARK: - Today hero

    @Test func resumeWinsAndDescribesWhereYouWere() {
        let resume = WatchTodayHeroBuilder.ResumeInput(
            title: "Push A", startedAt: Date(timeIntervalSince1970: 0),
            exercises: [("Bench", 4), ("OHP", 2)], plannedSets: ["ohp": 4])
        guard case .resume(_, let detail, _) = WatchTodayHeroBuilder.make(resume: resume, plan: nil) else {
            Issue.record("resume must lead")
            return
        }
        #expect(detail.contains("Bench"))
        #expect(detail.contains("2"))
        #expect(detail.contains("4"))
    }

    @Test func syncedEmptyTodayPlanDoesNotAskToOpenThePhoneAgain() {
        #expect(
            WatchTodayHeroBuilder.make(resume: nil, plan: nil, synced: true) ==
            .unplanned(synced: true))
        #expect(
            WatchTodayHeroBuilder.make(resume: nil, plan: nil, synced: false) ==
            .unplanned(synced: false))
    }

    @Test func plannedStrengthEstimatesMinutesOnlyFromKnownSets() {
        let withSets = WatchSync.TodayPlan(sessions: [
            .init(id: "s", kind: .strength, label: "Push A", exerciseNames: ["Bench"],
                  planPayload: WatchPlanPayload(strength: .init(prescriptions: [
                      PlannedExercisePrescription(exerciseName: "Bench", sets: Array(repeating:
                        PlannedSetPrescription(targetReps: 5), count: 6))])))
        ])
        guard case .planned(_, _, _, let minutes, _) = WatchTodayHeroBuilder.make(resume: nil, plan: withSets) else {
            Issue.record("planned strength expected")
            return
        }
        #expect(minutes == 13)

        let unknown = WatchSync.TodayPlan(sessions: [.init(id: "s", kind: .strength, label: "Push", exerciseNames: ["Bench"])])
        guard case .planned(_, _, _, let none, _) = WatchTodayHeroBuilder.make(resume: nil, plan: unknown) else {
            Issue.record("planned strength expected")
            return
        }
        #expect(none == nil, "never guess a duration")
    }

    @Test func restDayCarriesTheCoachNoteWithCitations() {
        let plan = WatchSync.TodayPlan(sessions: [
            .init(id: "r", kind: .rest, label: "Rest", adviceNote: "Readiness is low — consider keeping today lighter.",
                  adviceCitationIDs: WatchSync.TodayPlan.Session.adviceCitations)
        ])
        guard case .restDay(let advice) = WatchTodayHeroBuilder.make(resume: nil, plan: plan) else {
            Issue.record("rest day expected")
            return
        }
        #expect(advice?.citationIDs == WatchSync.TodayPlan.Session.adviceCitations)
    }

    @Test func todayPlanAdviceRoundTripsThroughTheContext() {
        let plan = WatchSync.TodayPlan(sessions: [
            .init(id: "s", kind: .strength, label: "Legs", adviceNote: "Consider a lighter session — 6 hard days in a row.",
                  adviceCitationIDs: ["meeusenOvertraining2013"])
        ])
        let decoded = WatchSync.TodayPlan.from(context: WatchSync.TodayPlan.contextDict(plan))
        #expect(decoded?.sessions.first?.adviceNote == plan.sessions[0].adviceNote)
        #expect(decoded?.sessions.first?.adviceCitationIDs == ["meeusenOvertraining2013"])
    }

    // MARK: - Receipts and cardio order

    @Test func receiptsSayWhereEachCopyIs() {
        let sending = WatchSaveReceipt.make(savedOnWatch: true, pendingTransfers: 3, phoneReachable: true, transferError: nil)
        #expect(sending.watch == .done)
        guard case .inProgress = sending.iPhone else {
            Issue.record("sending expected")
            return
        }
        guard case .waiting = sending.health else {
            Issue.record("health waits for the phone")
            return
        }

        let away = WatchSaveReceipt.make(savedOnWatch: true, pendingTransfers: 3, phoneReachable: false, transferError: nil)
        guard case .waiting = away.iPhone else {
            Issue.record("waiting expected")
            return
        }

        let done = WatchSaveReceipt.make(savedOnWatch: true, pendingTransfers: 0, phoneReachable: false, transferError: nil)
        #expect(done.iPhone == .done)
        #expect(done.health == .done)

        let failed = WatchSaveReceipt.make(savedOnWatch: true, pendingTransfers: 1, phoneReachable: true, transferError: "x")
        #expect(failed.iPhone == .failed("x"))
    }

    @Test func cardioTilesLearnTheOrder() {
        let order = WatchCardioTileOrder.ordered(["run", "cycle", "boxing", "hiit", "row", "swim"],
                                                 counts: ["swim": 9, "row": 4, "run": 4])
        #expect(order.tiles == ["swim", "run", "row", "cycle"])
        #expect(order.more == ["boxing", "hiit"])
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
struct WatchCardioRedesignTests {
    @Test func intervalToneIsWorkRestEndingOrEasy() {
        #expect(WatchIntervalPhaseTone.tone(for: .work) == .work)
        #expect(WatchIntervalPhaseTone.tone(for: .warning) == .ending)
        #expect(WatchIntervalPhaseTone.tone(for: .imminent) == .ending)
        #expect(WatchIntervalPhaseTone.tone(for: .rest) == .rest)
        #expect(WatchIntervalPhaseTone.tone(for: .neutral) == .easy)
    }

    @Test func planTargetShowsOnlyWhatWasPlanned() {
        #expect(WatchCardioPlanTarget.text(durationSeconds: nil, zone: nil) == nil)
        #expect(WatchCardioPlanTarget.text(durationSeconds: 0, zone: 9) == nil)
        #expect(WatchCardioPlanTarget.text(durationSeconds: 1800, zone: 2) == "Planned: 30 min · Zone 2")
        #expect(WatchCardioPlanTarget.text(durationSeconds: nil, zone: 3) == "Planned: Zone 3")
        #expect(WatchCardioPlanTarget.progress(elapsed: 900, durationSeconds: 1800) == 0.5)
        #expect(WatchCardioPlanTarget.progress(elapsed: 4000, durationSeconds: 1800) == 1)
        #expect(WatchCardioPlanTarget.progress(elapsed: 10, durationSeconds: nil) == nil)
    }
}
#endif
