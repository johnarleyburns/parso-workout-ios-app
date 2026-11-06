import XCTest
import CadenceCore
@testable import CadenceFeatures

final class TodayStartupPresentationTests: XCTestCase {
    private func plan(_ names: [String]) -> TodaySuggestedPlanPayload {
        TodaySuggestedPlanPayload(EditablePlan(
            title: "Fill the gaps",
            warmupMinutes: 5,
            cooldownMinutes: 3,
            exercises: names.map { name in
                EditableExercise(name: name,
                                 sets: [EditableSet(targetReps: 8, targetWeight: 50, loadMode: .straight)],
                                 notes: "")
            }))
    }

    func testDurableFullPlanWinsOverSingleExerciseCoachFallbackImmediately() {
        let durablePlan = plan(["Squat", "Bench Press", "Row", "Lunge"])
        let singleExerciseFallback = TodayHero(kind: .suggested, title: "Strength today",
                                                exercises: [.init(name: "Kettlebell Swing", detail: "3 × 10")])

        let hero = TodayStartupPresentation.hero(plan: durablePlan,
                                                  coachFallback: singleExerciseFallback,
                                                  reason: "Fill weekly gaps")

        XCTAssertEqual(hero?.title, "Fill the gaps")
        XCTAssertEqual(hero?.exercises.map(\.name), ["Squat", "Bench Press", "Row", "Lunge"])
    }

    func testCoachFallbackIsOnlyUsedWhenNoFullPlanIsAvailable() {
        let fallback = TodayHero(kind: .suggested, title: "Strength today",
                                 exercises: [.init(name: "Kettlebell Swing", detail: "3 × 10")])

        XCTAssertEqual(TodayStartupPresentation.hero(plan: nil, coachFallback: fallback, reason: nil), fallback)
    }

    func testStartupPlanIsLaunchableWithoutCoachOrHistory() {
        let fallback = TodayStartupPresentation.immediateFallback(
            style: .fitness,
            warmupMinutes: 5,
            cooldownMinutes: 3)

        XCTAssertFalse(fallback.exercises.isEmpty)
        XCTAssertGreaterThan(fallback.exercises.count, 1)
        XCTAssertEqual(fallback.warmupMinutes, 5)
        XCTAssertEqual(fallback.cooldownMinutes, 3)
    }

    func testStartupFallbackIsCompleteForEverySupportedStyle() {
        for style in SuggestedWorkoutStyle.allCases {
            let fallback = TodayStartupPresentation.immediateFallback(
                style: style, warmupMinutes: 0, cooldownMinutes: 0)
            XCTAssertGreaterThanOrEqual(fallback.exercises.count, 5, "\(style) must not regress to one exercise")
            XCTAssertTrue(fallback.exercises.allSatisfy { $0.sets.count == 3 })
        }
    }

    func testHeroUsesFullPlanSetAndRepDetails() {
        let payload = TodaySuggestedPlanPayload(EditablePlan(
            title: "Fill the gaps", warmupMinutes: 0, cooldownMinutes: 0,
            exercises: [EditableExercise(name: "Squat", sets: [
                EditableSet(targetReps: 6, targetWeight: 80, loadMode: .straight),
                EditableSet(targetReps: 8, targetWeight: 80, loadMode: .straight),
                EditableSet(targetReps: 8, targetWeight: 80, loadMode: .straight)], notes: "")]))

        let hero = TodayStartupPresentation.hero(plan: payload, coachFallback: nil, reason: nil)
        XCTAssertEqual(hero?.exercises, [.init(name: "Squat", detail: "3 × 6–8")])
    }

    func testPersonalizedResultCannotSilentlyReplaceVisibleStartupPlan() {
        let displayed = TodayStartupPresentation.immediateFallback(
            style: .fitness, warmupMinutes: 5, cooldownMinutes: 3)
        let personalized = plan(["Leg Press", "Incline Press", "Lat Pulldown", "Hamstring Curl"])

        XCTAssertEqual(
            TodaySuggestionReplacementGate.decide(displayed: displayed, freshlyComputed: personalized),
            .holdPending)
    }

    func testCacheMissStartupProducesLaunchableHeroInsteadOfLoading() {
        let fallback = TodayStartupPresentation.immediateFallback(
            style: .fitness, warmupMinutes: 5, cooldownMinutes: 3)
        let startupHero = TodayStartupPresentation.hero(plan: fallback, coachFallback: nil,
                                                         reason: "Personalizing when ready")

        let rendered = TodayHeroPresenter.hero(
            inProgress: nil, scheduled: nil, suggested: startupHero,
            fallbackRecommendation: nil, completedWorkoutCount: 2,
            recommendationReady: true)

        XCTAssertEqual(rendered.kind, .suggested)
        XCTAssertEqual(rendered.title, fallback.title)
        XCTAssertGreaterThan(rendered.exercises.count, 1)
    }
}
