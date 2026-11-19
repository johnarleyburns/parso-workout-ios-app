import Testing
import CadenceCore
import CadencePhoneFeatures
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

struct TodayStartupPresentationTests {
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

    @Test func durableFullPlanWinsOverSingleExerciseCoachFallbackImmediately() {
        let durablePlan = plan(["Squat", "Bench Press", "Row", "Lunge"])
        let singleExerciseFallback = TodayHero(kind: .suggested, title: "Strength today",
                                                exercises: [.init(name: "Kettlebell Swing", detail: "3 × 10")])

        let hero = TodayStartupPresentation.hero(plan: durablePlan,
                                                  coachFallback: singleExerciseFallback,
                                                  reason: "Fill weekly gaps")

        #expect(hero?.title == "Fill the gaps")
        #expect(hero?.exercises.map(\.name) == ["Squat", "Bench Press", "Row", "Lunge"])
    }

    @Test func coachFallbackIsOnlyUsedWhenNoFullPlanIsAvailable() {
        let fallback = TodayHero(kind: .suggested, title: "Strength today",
                                 exercises: [.init(name: "Kettlebell Swing", detail: "3 × 10")])

        #expect(TodayStartupPresentation.hero(plan: nil, coachFallback: fallback, reason: nil) == fallback)
    }

    @Test func startupPlanIsLaunchableWithoutCoachOrHistory() {
        let fallback = TodayStartupPresentation.immediateFallback(
            style: .fitness,
            warmupMinutes: 5,
            cooldownMinutes: 3)

        #expect(!fallback.exercises.isEmpty)
        #expect(fallback.exercises.count > 1)
        #expect(fallback.warmupMinutes == 5)
        #expect(fallback.cooldownMinutes == 3)
    }

    @Test func startupFallbackIsCompleteForEverySupportedStyle() {
        for style in SuggestedWorkoutStyle.allCases {
            let fallback = TodayStartupPresentation.immediateFallback(
                style: style, warmupMinutes: 0, cooldownMinutes: 0)
            #expect(fallback.exercises.count >= 5, "\(style) must not regress to one exercise")
            #expect(fallback.exercises.allSatisfy { $0.sets.count == 3 })
        }
    }

    @Test func heroUsesFullPlanSetAndRepDetails() {
        let payload = TodaySuggestedPlanPayload(EditablePlan(
            title: "Fill the gaps", warmupMinutes: 0, cooldownMinutes: 0,
            exercises: [EditableExercise(name: "Squat", sets: [
                EditableSet(targetReps: 6, targetWeight: 80, loadMode: .straight),
                EditableSet(targetReps: 8, targetWeight: 80, loadMode: .straight),
                EditableSet(targetReps: 8, targetWeight: 80, loadMode: .straight)], notes: "")]))

        let hero = TodayStartupPresentation.hero(plan: payload, coachFallback: nil, reason: nil)
        #expect(hero?.exercises == [.init(name: "Squat", detail: "3 × 6–8")])
    }

    @Test func personalizedResultCannotSilentlyReplaceVisibleStartupPlan() {
        let displayed = TodayStartupPresentation.immediateFallback(
            style: .fitness, warmupMinutes: 5, cooldownMinutes: 3)
        let personalized = plan(["Leg Press", "Incline Press", "Lat Pulldown", "Hamstring Curl"])

        #expect(
            TodaySuggestionReplacementGate.decide(displayed: displayed, freshlyComputed: personalized) ==
            .holdPending)
    }

    @Test func cacheMissStartupProducesLaunchableHeroInsteadOfLoading() {
        let fallback = TodayStartupPresentation.immediateFallback(
            style: .fitness, warmupMinutes: 5, cooldownMinutes: 3)
        let startupHero = TodayStartupPresentation.hero(plan: fallback, coachFallback: nil,
                                                         reason: "Personalizing when ready")

        let rendered = TodayHeroPresenter.hero(
            inProgress: nil, scheduled: nil, suggested: startupHero,
            fallbackRecommendation: nil, completedWorkoutCount: 2,
            recommendationReady: true)

        #expect(rendered.kind == .suggested)
        #expect(rendered.title == fallback.title)
        #expect(rendered.exercises.count > 1)
    }
}
