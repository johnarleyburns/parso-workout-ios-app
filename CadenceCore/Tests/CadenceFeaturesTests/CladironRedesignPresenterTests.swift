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
        XCTAssertEqual(MuscleHeatPresenter.level(sets: 6, target: 12), .high)
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
        let scheduled = TodayHero(kind: .scheduled, title: "Scheduled")
        let inProgress = TodayHero(kind: .inProgress, title: "Resume")
        XCTAssertEqual(TodayHeroPresenter.hero(inProgress: inProgress, scheduled: scheduled,
                                               suggested: suggested, completedWorkoutCount: 10).kind, .inProgress)
        XCTAssertEqual(TodayHeroPresenter.hero(inProgress: nil, scheduled: scheduled,
                                               suggested: suggested, completedWorkoutCount: 10).kind, .scheduled)
        XCTAssertEqual(TodayHeroPresenter.hero(inProgress: nil, scheduled: nil,
                                               suggested: suggested, completedWorkoutCount: 1).kind, .needsHistory)
    }

    func testTodayHeroCapsExercises() {
        let lines = (0..<8).map { TodayHero.Line(name: "\($0)", detail: "3 × 5") }
        let hero = TodayHero(kind: .suggested, title: "Lift", exercises: lines)
        XCTAssertEqual(hero.exercises.count, 5)
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
}
