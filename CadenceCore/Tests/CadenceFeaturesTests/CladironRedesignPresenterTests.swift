import Foundation
import Testing
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures
import CadencePhoneFeatures

struct CladironRedesignPresenterTests {
    @Test func weightSuggestionCopyUsesOwnerGrammar() {
        #expect(WeightSuggestionCopy.source(performerName: nil, exercise: "Deadlift")
            .contains("your previous Deadlift"))
    }

    @Test func weightSuggestionCopyUsesPartnerGrammar() {
        #expect(WeightSuggestionCopy.source(performerName: "Audrey", exercise: "Deadlift")
            .contains("Audrey's previous Deadlift"))
        #expect(WeightSuggestionCopy.source(performerName: "Chris", exercise: "Deadlift")
            .contains("Chris's previous Deadlift"))
    }

    @Test func heatBoundaries() {
        #expect(MuscleHeatPresenter.level(sets: 4, target: 12) == .mid)
        #expect(MuscleHeatPresenter.level(sets: 6, target: 12) == .mid)
        #expect(MuscleHeatPresenter.level(sets: 9, target: 12) == .onTarget)
        #expect(MuscleHeatPresenter.level(sets: 0, target: 0) == .none)
    }

    @Test func heatMostBehindUsesCanonicalTieOrder() {
        let all = [MuscleHeat(id: .abdominals, sets: 0, target: 12, level: .none, accessibilityLabel: ""),
                   MuscleHeat(id: .calves, sets: 0, target: 12, level: .none, accessibilityLabel: ""),
                   MuscleHeat(id: .forearms, sets: 0, target: 12, level: .none, accessibilityLabel: "")]
        #expect(MuscleHeatPresenter.mostBehind(all).map(\.id) == [.calves, .abdominals, .forearms])
    }

    @Test func todayHeroPrecedenceAndHistoryGate() {
        let suggested = TodayHero(kind: .suggested, title: "Suggested")
        let fallback = TodayHero(kind: .suggested, title: "Coach fallback")
        let scheduled = TodayHero(kind: .scheduled, title: "Scheduled")
        let inProgress = TodayHero(kind: .inProgress, title: "Resume")
        #expect(TodayHeroPresenter.hero(inProgress: inProgress, scheduled: scheduled,
                                               suggested: suggested, completedWorkoutCount: 10).kind == .inProgress)
        #expect(TodayHeroPresenter.hero(inProgress: nil, scheduled: scheduled,
                                               suggested: suggested, completedWorkoutCount: 10).kind == .scheduled)
        #expect(TodayHeroPresenter.hero(inProgress: nil, scheduled: nil,
                                               suggested: suggested, completedWorkoutCount: 1).kind == .needsHistory)
        let starter = TodayHero(kind: .suggested, title: "Starter")
        let starterHero = TodayHeroPresenter.hero(inProgress: nil, scheduled: nil, suggested: nil,
                                                  starter: starter, completedWorkoutCount: 0)
        #expect(starterHero.kind == .starter)
        #expect(starterHero.title == "Starter")
        #expect(TodayHeroPresenter.hero(inProgress: nil, scheduled: nil, suggested: nil,
                                               starter: nil, completedWorkoutCount: 0).kind == .loading)
        #expect(TodayHeroPresenter.hero(inProgress: nil, scheduled: nil, suggested: nil,
                                               starter: starter, completedWorkoutCount: 1).kind == .needsHistory)
        #expect(TodayHeroPresenter.hero(inProgress: nil, scheduled: nil,
                                               suggested: nil, fallbackRecommendation: fallback,
                                               completedWorkoutCount: 10).title == "Coach fallback")
    }

    @Test func todayHeroDoesNotInventRecoveryWhenCoachHasARecommendation() {
        let fallback = TodayHero(kind: .suggested, title: "Strength session")
        let hero = TodayHeroPresenter.hero(inProgress: nil, scheduled: nil,
                                           suggested: nil, fallbackRecommendation: fallback,
                                           completedWorkoutCount: 4)
        #expect(hero.kind == .suggested)
        #expect(hero.title != "Recovery day")
    }

    @Test func todayHeroShowsLoadingUntilTheRecommendationIsReady() {
        let hero = TodayHeroPresenter.hero(inProgress: nil, scheduled: nil,
                                           suggested: nil, completedWorkoutCount: 4,
                                           recommendationReady: false)
        #expect(hero.kind == .loading)
        #expect(hero.title != "Recovery day")
    }

    @Test func todayHeroRetainsEveryExercise() {
        let lines = (0..<8).map { TodayHero.Line(name: "Move \($0)", detail: "3 × 5") }
        let hero = TodayHero(kind: .suggested, title: "Lift", exercises: lines)
        #expect(hero.exercises == lines)
    }

    @Test func disclosureWideShowsAllAndConstrainedIsTruthful() {
        let lines = (0..<8).map { TodayHero.Line(name: "Move \($0)", detail: "3 × 5") }
        let wide = TodayExerciseDisclosure(lines: lines, capacity: 8)
        #expect(wide.visible.count == 8)
        #expect(wide.summaryText == nil)
        #expect(wide.accessibilityLabel == nil)

        let narrow = TodayExerciseDisclosure(lines: lines, capacity: 5)
        #expect(narrow.visible.count == 5)
        #expect(narrow.hiddenCount == 3)
        #expect(narrow.summaryText == "… +3 more")
        let label = narrow.accessibilityLabel ?? ""
        #expect(label.contains("8 in total"))
        #expect(label.contains("Move 5") && label.contains("Move 7"))
        #expect(narrow.visible + narrow.hidden == lines)
    }

    @Test func disclosureFiveOrFewerUnchanged() {
        let lines = (0..<3).map { TodayHero.Line(name: "Move \($0)", detail: "3 × 5") }
        let d = TodayExerciseDisclosure(lines: lines, capacity: 3)
        #expect(d.visible == lines)
        #expect(d.hiddenCount == 0)
    }

    @Test func prMomentExcludesTiesWarmupsAndPartnerSets() {
        #expect(PRMomentPresenter.moment(exercise: "Squat", loadText: "200 lb",
                                              changeText: "up 5 lb", isNewPR: false,
                                              isWarmup: false, isPartnerSet: false) == nil)
        #expect(PRMomentPresenter.moment(exercise: "Squat", loadText: "200 lb",
                                              changeText: "up 5 lb", isNewPR: true,
                                              isWarmup: true, isPartnerSet: false) == nil)
        #expect(PRMomentPresenter.moment(exercise: "Squat", loadText: "200 lb",
                                                changeText: "up 5 lb", isNewPR: true,
                                                isWarmup: false, isPartnerSet: true,
                                                performerName: "Audrey")?.performerName == "Audrey")
    }

    @Test func prTakeoverContainsPreviousAndNewValues() {
        let event = PREvent(exerciseName: "Bench Press", date: Date(), kind: .weight,
                            value: 60, reps: 5, weightKg: 60, previous: 57)
        let takeover = PRMomentPresenter.takeover(for: event, unit: .kilograms)
        #expect(takeover.exerciseName == "Bench Press")
        #expect(takeover.newValue == "60 kg")
        #expect(takeover.previousValue == "57 kg")
        #expect(takeover.improvement == "+3 kg over previous")
    }
}
