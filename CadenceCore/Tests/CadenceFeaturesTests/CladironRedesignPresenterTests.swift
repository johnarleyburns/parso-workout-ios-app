import XCTest
import CadenceCore
import CadenceFeatures

final class CladironRedesignPresenterTests: XCTestCase {
    func testWeightSuggestionCopyUsesOwnerGrammar() {
        XCTAssertTrue(WeightSuggestionCopy.source(performerName: nil, exercise: "Deadlift")
            .contains("your previous Deadlift"))
    }

    func testWeightSuggestionCopyUsesPartnerGrammar() {
        XCTAssertTrue(WeightSuggestionCopy.source(performerName: "Audrey", exercise: "Deadlift")
            .contains("Audrey's previous Deadlift"))
        XCTAssertTrue(WeightSuggestionCopy.source(performerName: "Chris", exercise: "Deadlift")
            .contains("Chris's previous Deadlift"))
    }

    func testHeatBoundaries() {
        XCTAssertEqual(MuscleHeatPresenter.level(sets: 4, target: 12), .mid)
        XCTAssertEqual(MuscleHeatPresenter.level(sets: 6, target: 12), .mid)
        XCTAssertEqual(MuscleHeatPresenter.level(sets: 9, target: 12), .onTarget)
        XCTAssertEqual(MuscleHeatPresenter.level(sets: 0, target: 0), .none)
    }

    func testHeatMostBehindUsesCanonicalTieOrder() {
        let all = [MuscleHeat(id: .abdominals, sets: 0, target: 12, level: .none, accessibilityLabel: ""),
                   MuscleHeat(id: .calves, sets: 0, target: 12, level: .none, accessibilityLabel: ""),
                   MuscleHeat(id: .forearms, sets: 0, target: 12, level: .none, accessibilityLabel: "")]
        XCTAssertEqual(MuscleHeatPresenter.mostBehind(all).map(\.id), [.calves, .abdominals, .forearms])
    }

    func testTodayHeroPrecedenceAndHistoryGate() {
        let suggested = TodayHero(kind: .suggested, title: "Suggested")
        let fallback = TodayHero(kind: .suggested, title: "Coach fallback")
        let scheduled = TodayHero(kind: .scheduled, title: "Scheduled")
        let inProgress = TodayHero(kind: .inProgress, title: "Resume")
        XCTAssertEqual(TodayHeroPresenter.hero(inProgress: inProgress, scheduled: scheduled,
                                               suggested: suggested, completedWorkoutCount: 10).kind, .inProgress)
        XCTAssertEqual(TodayHeroPresenter.hero(inProgress: nil, scheduled: scheduled,
                                               suggested: suggested, completedWorkoutCount: 10).kind, .scheduled)
        XCTAssertEqual(TodayHeroPresenter.hero(inProgress: nil, scheduled: nil,
                                               suggested: suggested, completedWorkoutCount: 1).kind, .needsHistory)
        XCTAssertEqual(TodayHeroPresenter.hero(inProgress: nil, scheduled: nil,
                                               suggested: nil, fallbackRecommendation: fallback,
                                               completedWorkoutCount: 10).title, "Coach fallback")
    }

    func testTodayHeroDoesNotInventRecoveryWhenCoachHasARecommendation() {
        let fallback = TodayHero(kind: .suggested, title: "Strength session")
        let hero = TodayHeroPresenter.hero(inProgress: nil, scheduled: nil,
                                           suggested: nil, fallbackRecommendation: fallback,
                                           completedWorkoutCount: 4)
        XCTAssertEqual(hero.kind, .suggested)
        XCTAssertNotEqual(hero.title, "Recovery day")
    }

    func testTodayHeroShowsLoadingUntilTheRecommendationIsReady() {
        let hero = TodayHeroPresenter.hero(inProgress: nil, scheduled: nil,
                                           suggested: nil, completedWorkoutCount: 4,
                                           recommendationReady: false)
        XCTAssertEqual(hero.kind, .loading)
        XCTAssertNotEqual(hero.title, "Recovery day")
    }

    func testTodayHeroRetainsEveryExercise() {
        let lines = (0..<8).map { TodayHero.Line(name: "Move \($0)", detail: "3 × 5") }
        let hero = TodayHero(kind: .suggested, title: "Lift", exercises: lines)
        XCTAssertEqual(hero.exercises, lines)
    }

    func testDisclosureWideShowsAllAndConstrainedIsTruthful() {
        let lines = (0..<8).map { TodayHero.Line(name: "Move \($0)", detail: "3 × 5") }
        let wide = TodayExerciseDisclosure(lines: lines, capacity: 8)
        XCTAssertEqual(wide.visible.count, 8)
        XCTAssertNil(wide.summaryText)
        XCTAssertNil(wide.accessibilityLabel)

        let narrow = TodayExerciseDisclosure(lines: lines, capacity: 5)
        XCTAssertEqual(narrow.visible.count, 5)
        XCTAssertEqual(narrow.hiddenCount, 3)
        XCTAssertEqual(narrow.summaryText, "… +3 more")
        let label = narrow.accessibilityLabel ?? ""
        XCTAssertTrue(label.contains("8 in total"))
        XCTAssertTrue(label.contains("Move 5") && label.contains("Move 7"))
        XCTAssertEqual(narrow.visible + narrow.hidden, lines)
    }

    func testDisclosureFiveOrFewerUnchanged() {
        let lines = (0..<3).map { TodayHero.Line(name: "Move \($0)", detail: "3 × 5") }
        let d = TodayExerciseDisclosure(lines: lines, capacity: 3)
        XCTAssertEqual(d.visible, lines)
        XCTAssertEqual(d.hiddenCount, 0)
    }

    func testPRMomentExcludesTiesWarmupsAndPartnerSets() {
        XCTAssertNil(PRMomentPresenter.moment(exercise: "Squat", loadText: "200 lb",
                                              changeText: "up 5 lb", isNewPR: false,
                                              isWarmup: false, isPartnerSet: false))
        XCTAssertNil(PRMomentPresenter.moment(exercise: "Squat", loadText: "200 lb",
                                              changeText: "up 5 lb", isNewPR: true,
                                              isWarmup: true, isPartnerSet: false))
        XCTAssertEqual(PRMomentPresenter.moment(exercise: "Squat", loadText: "200 lb",
                                                changeText: "up 5 lb", isNewPR: true,
                                                isWarmup: false, isPartnerSet: true,
                                                performerName: "Audrey")?.performerName, "Audrey")
    }

    func testPRTakeoverContainsPreviousAndNewValues() {
        let event = PREvent(exerciseName: "Bench Press", date: Date(), kind: .weight,
                            value: 60, reps: 5, weightKg: 60, previous: 57)
        let takeover = PRMomentPresenter.takeover(for: event, unit: .kilograms)
        XCTAssertEqual(takeover.exerciseName, "Bench Press")
        XCTAssertEqual(takeover.newValue, "60 kg")
        XCTAssertEqual(takeover.previousValue, "57 kg")
        XCTAssertEqual(takeover.improvement, "+3 kg over previous")
    }
}
