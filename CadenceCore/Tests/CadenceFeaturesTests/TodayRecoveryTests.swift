#if canImport(SwiftData)
import Foundation
import Testing
import SwiftData
import CadencePhoneFeatures
@testable import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures

struct TodayRecoveryTests {
    private func decision(_ session: CoachSession, deferred: [DeferredCandidate] = []) -> CoachDecision {
        CoachDecision(id: "test", generatedAt: Date(), primary: session, deferred: deferred,
                      weeklyBalance: .empty, confidence: .high)
    }

    @Test func cardioAndAssessmentNeverBecomeRecovery() {
        for kind in [CoachSessionKind.easyAerobic, .moderateAerobic, .vo2Intervals, .assessment] {
            let session = CoachSession(id: "actual", kind: kind, title: "Actual choice",
                                       subtitle: "Actual explanation", durationMinutes: 15,
                                       citationIds: ["ekelundActivityMortality2016"])
            let hero = TodayHeroPresenter.recommendation(decision(session))
            #expect(hero.kind == .suggested)
            #expect(hero.title == session.title)
            #expect(hero.reason == session.subtitle)
            #expect(hero.estimatedMinutes == 15)
            let presented = TodayHeroPresenter.hero(inProgress: nil, scheduled: nil, suggested: nil,
                fallbackRecommendation: hero, completedWorkoutCount: 10, recommendationReady: true)
            #expect(presented.kind == .suggested)
            #expect(presented.title == session.title)
        }
    }

    @Test func fallbackPreservesStrengthPrescription() {
        let session = CoachSession(id: "strength", kind: .strength, title: "Strength",
            exercises: [.init(name: "Bodyweight Squat", sets: 3, repsLow: 8, repsHigh: 12)])
        let hero = TodayHeroPresenter.recommendation(decision(session))
        #expect(hero.kind == .suggested)
        #expect(hero.exercises.first?.detail == "3 × 8–12")
    }

    @Test func recoveryExplainsDeferredTrainingAndKeepsScience() {
        let strength = CoachSession(id: "strength", kind: .strength, title: "Hard workout")
        let reason = DecisionReason(id: "recovery", message: "Recent training needs more recovery.",
                                    citationIds: ["schoenfeld2021"])
        let recovery = CoachSession(id: "rest", kind: .rest, title: "Rest day", subtitle: "Keep today light.",
                                    citationIds: ["meeusenOvertraining2013"])
        let hero = TodayHeroPresenter.recommendation(decision(recovery, deferred: [
            DeferredCandidate(session: strength, reason: reason),
            DeferredCandidate(session: strength, reason: reason)
        ]))
        #expect(hero.kind == .restDay)
        #expect(hero.title == "Rest day")
        #expect(hero.exercises.isEmpty)
        #expect(hero.reason?.contains(reason.message) == true)
        #expect(hero.reason?.components(separatedBy: reason.message).count == 2)
        for id in hero.citationIDs { #expect(CitationRegistry.citation(forId: id) != nil) }
    }

    @Test func easyOptionsAreLightAndLaunchable() {
        let plan = RecoveryOptionsPresenter.resistancePlan()
        #expect(plan.exercises.count == 2)
        for exercise in plan.exercises {
            #expect(exercise.sets.count == 1)
            #expect(exercise.sets.first?.targetReps == 8)
            #expect(exercise.sets.first?.targetWeight == nil)
            #expect(exercise.sets.first?.loadMode == .bodyweight)
            #expect(ExerciseLibrary.byName[exercise.name.lowercased()] != nil)
            #expect(exercise.notes.contains("at least 5 reps"))
        }
        for session in RecoveryOptionsPresenter.cardio {
            #expect(session.intensity == .easy)
            #expect(session.durationMinutes == 15)
            #expect(CoachRouter.destination(for: session) != .none)
        }
        for id in RecoveryOptionsPresenter.citationIDs { #expect(CitationRegistry.citation(forId: id) != nil) }
    }
    @Test func excludedAirSquatNeverAppearsInRecoveryDraft() throws {
        let airSquat = try #require(ExerciseLibrary.template(matching: "Air Squat"))
        let recoverySquat = try #require(ExerciseLibrary.template(matching: "Bodyweight Squat"))
        #expect(ExerciseSuggestionExclusionKey.forTemplate(airSquat) ==
                       ExerciseSuggestionExclusionKey.forTemplate(recoverySquat))
        let excluded = Set([ExerciseSuggestionExclusionKey.forTemplate(airSquat)])
        let legacy = Set(["legacy:\(ExerciseLibrary.dedupKey("Air Squat"))"])
        #expect(RecoveryOptionsPresenter.resistancePlan(excludedKeys: legacy).exercises.count == 1)
        let plan = RecoveryOptionsPresenter.resistancePlan(excludedKeys: excluded)
        #expect(!plan.exercises.isEmpty)
        for exercise in plan.exercises {
            let template = try #require(ExerciseLibrary.template(matching: exercise.name))
            #expect(!excluded.contains(ExerciseSuggestionExclusionKey.forTemplate(template)))
        }
    }

    @Test func allRecoveryResistanceExcludedLeavesOnlyCardioOptions() throws {
        let keys = try Set(RecoveryOptionsPresenter.resistancePlan().exercises.map {
            ExerciseSuggestionExclusionKey.forTemplate(try #require(ExerciseLibrary.template(matching: $0.name)))
        })
        #expect(RecoveryOptionsPresenter.resistancePlan(excludedKeys: keys).exercises.isEmpty)
        #expect(RecoveryOptionsPresenter.cardio.count == 2)
    }

    @Test func coverageShadingUsesAbsoluteWeeklySetThresholds() {
        for target in [0.0, 8, 12, 20] {
            for (sets, expected) in [(0.0, 0.12), (0.5, 0.25), (3.99, 0.25),
                                     (4.0, 0.5), (7.99, 0.5), (8.0, 1.0), (20.0, 1.0)] {
                #expect(MuscleHeatPresenter.opacity(for: MuscleHeatPresenter.level(sets: sets, target: target)) == expected)
            }
        }
    }

    @MainActor
    @Test func persistedExclusionFiltersRecoveryAndAllowingRestoresIt() throws {
        let context = ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
        let template = try #require(ExerciseLibrary.template(matching: "Air Squat"))
        let record = try ExerciseSuggestionExclusionStore.setExcluded(
            key: ExerciseSuggestionExclusionKey.forTemplate(template), name: template.name,
            reason: .personalPreference, in: context)
        let keys = try ExerciseSuggestionExclusionStore.activeKeys(in: context)
        #expect(RecoveryOptionsPresenter.resistancePlan(excludedKeys: keys).exercises.count == 1)
        try ExerciseSuggestionExclusionStore.allow(record, in: context)
        #expect(RecoveryOptionsPresenter.resistancePlan(
            excludedKeys: try ExerciseSuggestionExclusionStore.activeKeys(in: context)).exercises.count == 2)
    }

}
#endif
