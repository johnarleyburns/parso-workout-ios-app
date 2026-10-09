import XCTest
import SwiftData
@testable import CadenceCore
import CadenceFeatures

final class TodayRecoveryTests: XCTestCase {
    private func decision(_ session: CoachSession, deferred: [DeferredCandidate] = []) -> CoachDecision {
        CoachDecision(id: "test", generatedAt: Date(), primary: session, deferred: deferred,
                      weeklyBalance: .empty, confidence: .high)
    }

    func testCardioAndAssessmentNeverBecomeRecovery() {
        for kind in [CoachSessionKind.easyAerobic, .moderateAerobic, .vo2Intervals, .assessment] {
            let session = CoachSession(id: "actual", kind: kind, title: "Actual choice",
                                       subtitle: "Actual explanation", durationMinutes: 15,
                                       citationIds: ["ekelundActivityMortality2016"])
            let hero = TodayHeroPresenter.recommendation(decision(session))
            XCTAssertEqual(hero.kind, .suggested)
            XCTAssertEqual(hero.title, session.title)
            XCTAssertEqual(hero.reason, session.subtitle)
            XCTAssertEqual(hero.estimatedMinutes, 15)
            let presented = TodayHeroPresenter.hero(inProgress: nil, scheduled: nil, suggested: nil,
                fallbackRecommendation: hero, completedWorkoutCount: 10, recommendationReady: true)
            XCTAssertEqual(presented.kind, .suggested)
            XCTAssertEqual(presented.title, session.title)
        }
    }

    func testFallbackPreservesStrengthPrescription() {
        let session = CoachSession(id: "strength", kind: .strength, title: "Strength",
            exercises: [.init(name: "Bodyweight Squat", sets: 3, repsLow: 8, repsHigh: 12)])
        let hero = TodayHeroPresenter.recommendation(decision(session))
        XCTAssertEqual(hero.kind, .suggested)
        XCTAssertEqual(hero.exercises.first?.detail, "3 × 8–12")
    }

    func testRecoveryExplainsDeferredTrainingAndKeepsScience() {
        let strength = CoachSession(id: "strength", kind: .strength, title: "Hard workout")
        let reason = DecisionReason(id: "recovery", message: "Recent training needs more recovery.",
                                    citationIds: ["schoenfeld2021"])
        let recovery = CoachSession(id: "rest", kind: .rest, title: "Rest day", subtitle: "Keep today light.",
                                    citationIds: ["meeusenOvertraining2013"])
        let hero = TodayHeroPresenter.recommendation(decision(recovery, deferred: [
            DeferredCandidate(session: strength, reason: reason),
            DeferredCandidate(session: strength, reason: reason)
        ]))
        XCTAssertEqual(hero.kind, .restDay)
        XCTAssertEqual(hero.title, "Rest day")
        XCTAssertTrue(hero.exercises.isEmpty)
        XCTAssertTrue(hero.reason?.contains(reason.message) == true)
        XCTAssertEqual(hero.reason?.components(separatedBy: reason.message).count, 2)
        for id in hero.citationIDs { XCTAssertNotNil(CitationRegistry.citation(forId: id)) }
    }

    func testEasyOptionsAreLightAndLaunchable() {
        let plan = RecoveryOptionsPresenter.resistancePlan()
        XCTAssertEqual(plan.exercises.count, 2)
        for exercise in plan.exercises {
            XCTAssertEqual(exercise.sets.count, 1)
            XCTAssertEqual(exercise.sets.first?.targetReps, 8)
            XCTAssertNil(exercise.sets.first?.targetWeight)
            XCTAssertEqual(exercise.sets.first?.loadMode, .bodyweight)
            XCTAssertNotNil(ExerciseLibrary.byName[exercise.name.lowercased()])
            XCTAssertTrue(exercise.notes.contains("at least 5 reps"))
        }
        for session in RecoveryOptionsPresenter.cardio {
            XCTAssertEqual(session.intensity, .easy)
            XCTAssertEqual(session.durationMinutes, 15)
            XCTAssertNotEqual(CoachRouter.destination(for: session), .none)
        }
        for id in RecoveryOptionsPresenter.citationIDs { XCTAssertNotNil(CitationRegistry.citation(forId: id)) }
    }
    func testExcludedAirSquatNeverAppearsInRecoveryDraft() throws {
        let airSquat = try XCTUnwrap(ExerciseLibrary.template(matching: "Air Squat"))
        let recoverySquat = try XCTUnwrap(ExerciseLibrary.template(matching: "Bodyweight Squat"))
        XCTAssertEqual(ExerciseSuggestionExclusionKey.forTemplate(airSquat),
                       ExerciseSuggestionExclusionKey.forTemplate(recoverySquat))
        let excluded = Set([ExerciseSuggestionExclusionKey.forTemplate(airSquat)])
        let legacy = Set(["legacy:\(ExerciseLibrary.dedupKey("Air Squat"))"])
        XCTAssertEqual(RecoveryOptionsPresenter.resistancePlan(excludedKeys: legacy).exercises.count, 1)
        let plan = RecoveryOptionsPresenter.resistancePlan(excludedKeys: excluded)
        XCTAssertFalse(plan.exercises.isEmpty)
        for exercise in plan.exercises {
            let template = try XCTUnwrap(ExerciseLibrary.template(matching: exercise.name))
            XCTAssertFalse(excluded.contains(ExerciseSuggestionExclusionKey.forTemplate(template)))
        }
    }

    func testAllRecoveryResistanceExcludedLeavesOnlyCardioOptions() throws {
        let keys = try Set(RecoveryOptionsPresenter.resistancePlan().exercises.map {
            ExerciseSuggestionExclusionKey.forTemplate(try XCTUnwrap(ExerciseLibrary.template(matching: $0.name)))
        })
        XCTAssertTrue(RecoveryOptionsPresenter.resistancePlan(excludedKeys: keys).exercises.isEmpty)
        XCTAssertEqual(RecoveryOptionsPresenter.cardio.count, 2)
    }

    func testCoverageShadingUsesAbsoluteWeeklySetThresholds() {
        for target in [0.0, 8, 12, 20] {
            for (sets, expected) in [(0.0, 0.12), (0.5, 0.25), (3.99, 0.25),
                                     (4.0, 0.5), (7.99, 0.5), (8.0, 1.0), (20.0, 1.0)] {
                XCTAssertEqual(MuscleHeatPresenter.opacity(for: MuscleHeatPresenter.level(sets: sets, target: target)), expected)
            }
        }
    }

    func testHeroAllocationDependsOnlyOnViewport() {
        XCTAssertEqual(TodayHeroLayout.height(viewportHeight: 760), 380)
        XCTAssertEqual(TodayHeroLayout.height(viewportHeight: 500), 320)
        XCTAssertEqual(TodayHeroLayout.height(viewportHeight: 1200), 440)
    }

    @MainActor
    func testPersistedExclusionFiltersRecoveryAndAllowingRestoresIt() throws {
        let context = ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
        let template = try XCTUnwrap(ExerciseLibrary.template(matching: "Air Squat"))
        let record = try ExerciseSuggestionExclusionStore.setExcluded(
            key: ExerciseSuggestionExclusionKey.forTemplate(template), name: template.name,
            reason: .personalPreference, in: context)
        let keys = try ExerciseSuggestionExclusionStore.activeKeys(in: context)
        XCTAssertEqual(RecoveryOptionsPresenter.resistancePlan(excludedKeys: keys).exercises.count, 1)
        try ExerciseSuggestionExclusionStore.allow(record, in: context)
        XCTAssertEqual(RecoveryOptionsPresenter.resistancePlan(
            excludedKeys: try ExerciseSuggestionExclusionStore.activeKeys(in: context)).exercises.count, 2)
    }

}
