import XCTest
import CadenceCore
@testable import CadenceFeatures

/// Field test 2026-08-18 #8/#9/#11: the Coach's Suggestions card's block order,
/// visibility and CTA rule. The view renders whatever this returns, so "the
/// suggested workout is last" is asserted here rather than in the simulator.
final class HomeCoachSectionPresenterTests: XCTestCase {

    private func suggestion(_ id: String, tone: HomeSuggestion.Tone = .neutral) -> HomeSuggestion {
        HomeSuggestion(id: id,
                       category: tone == .warning ? .safety : .progress,
                       title: "Title \(id)",
                       message: "Message \(id)",
                       citationID: nil,
                       sourceClaimKey: "claim.\(id)",
                       priority: 0,
                       confidence: 3)
    }

    private func session(exercises: Int = 3,
                         subtitle: String = "It closes this week's chest deficit.",
                         payload: CoachSession.LaunchPayload = .strengthPlan("push")) -> CoachSession {
        CoachSession(
            id: "session",
            kind: .strength,
            title: "Upper body — push emphasis",
            subtitle: subtitle,
            exercises: (0..<exercises).map {
                CoachSession.RecommendedExercise(name: "Exercise \($0)", sets: 3,
                                                 repsLow: 8, repsHigh: 12, loadKg: 40)
            },
            launchPayload: payload)
    }

    private func isSuggestedWorkout(_ block: HomeCoachSectionPresenter.Block) -> Bool {
        if case .suggestedWorkout = block { return true }
        return false
    }

    func testHeadingIsAlwaysFirst() {
        XCTAssertEqual(HomeCoachSectionPresenter.blocks(suggestions: [], recommendation: nil,
                                                        expanded: false).first, .heading)
        XCTAssertEqual(HomeCoachSectionPresenter.blocks(suggestions: [suggestion("a")],
                                                        recommendation: session(),
                                                        expanded: true).first, .heading)
    }

    func testSuggestedWorkoutIsAlwaysTheLastBlock() {
        for expanded in [false, true] {
            let blocks = HomeCoachSectionPresenter.blocks(
                suggestions: [suggestion("a"), suggestion("b"), suggestion("c")],
                recommendation: session(), expanded: expanded)
            XCTAssertTrue(isSuggestedWorkout(blocks.last!),
                          "The suggested workout must render after the suggestion list (expanded: \(expanded))")
            XCTAssertEqual(blocks.filter(isSuggestedWorkout).count, 1)
        }
    }

    func testShowMoreOnlyAppearsWithMoreThanOneSuggestion() {
        let one = HomeCoachSectionPresenter.blocks(suggestions: [suggestion("a")],
                                                   recommendation: nil, expanded: false)
        XCTAssertFalse(one.contains(.showMore(expanded: false)))

        let two = HomeCoachSectionPresenter.blocks(suggestions: [suggestion("a"), suggestion("b")],
                                                   recommendation: nil, expanded: false)
        XCTAssertTrue(two.contains(.showMore(expanded: false)))
    }

    func testCollapsedShowsOnlyTheFirstSuggestion() {
        let blocks = HomeCoachSectionPresenter.blocks(
            suggestions: [suggestion("a"), suggestion("b"), suggestion("c")],
            recommendation: nil, expanded: false)
        XCTAssertEqual(blocks.compactMap { if case let .suggestion(s) = $0 { return s.id } else { return nil } },
                       ["a"])
    }

    func testExpandedShowsEverySuggestion() {
        let blocks = HomeCoachSectionPresenter.blocks(
            suggestions: [suggestion("a"), suggestion("b"), suggestion("c")],
            recommendation: nil, expanded: true)
        XCTAssertEqual(blocks.compactMap { if case let .suggestion(s) = $0 { return s.id } else { return nil } },
                       ["a", "b", "c"])
    }

    func testDividerOnlyAppearsBetweenSuggestionsAndTheWorkout() {
        let blocks = HomeCoachSectionPresenter.blocks(suggestions: [suggestion("a")],
                                                       recommendation: session(), expanded: false)
        let dividerIndex = blocks.firstIndex(of: .divider)
        XCTAssertNotNil(dividerIndex)
        XCTAssertTrue(isSuggestedWorkout(blocks[dividerIndex! + 1]),
                      "The divider must sit immediately above the suggested workout")

        let noWorkout = HomeCoachSectionPresenter.blocks(suggestions: [suggestion("a")],
                                                          recommendation: nil, expanded: false)
        XCTAssertFalse(noWorkout.contains(.divider),
                       "No workout block means nothing to divide from")
    }

    func testNoDividerWhenThereAreNoSuggestions() {
        let blocks = HomeCoachSectionPresenter.blocks(suggestions: [], recommendation: session(),
                                                       expanded: false)
        XCTAssertFalse(blocks.contains(.divider))
        XCTAssertTrue(isSuggestedWorkout(blocks.last!))
    }

    func testNoSuggestedWorkoutBlockForRecoveryOrRestRecommendations() {
        for payload in [CoachSession.LaunchPayload.recovery, .rest, .assessment] {
            let blocks = HomeCoachSectionPresenter.blocks(
                suggestions: [suggestion("a")],
                recommendation: session(payload: payload), expanded: false)
            XCTAssertFalse(blocks.contains(where: isSuggestedWorkout),
                           "\(payload) has nothing to launch, so it renders no workout block")
            XCTAssertFalse(blocks.contains(.divider))
        }
    }

    func testShowsPrimaryActionOnlyWhenARecommendationIsLaunchable() {
        XCTAssertFalse(HomeCoachSectionPresenter.showsPrimaryAction(recommendation: nil))
        XCTAssertFalse(HomeCoachSectionPresenter.showsPrimaryAction(recommendation: session(payload: .rest)))
        XCTAssertFalse(HomeCoachSectionPresenter.showsPrimaryAction(recommendation: session(payload: .recovery)))
        XCTAssertTrue(HomeCoachSectionPresenter.showsPrimaryAction(recommendation: session()))
        XCTAssertTrue(HomeCoachSectionPresenter.showsPrimaryAction(
            recommendation: session(payload: .cardio(type: "run", durationMinutes: 30))))
    }

    func testPreviewExercisesCapAtSixWithAdditionalCount() {
        let nine = session(exercises: 9)
        XCTAssertEqual(HomeCoachSectionPresenter.previewExercises(nine).count, 6)
        XCTAssertEqual(HomeCoachSectionPresenter.additionalExerciseCount(nine), 3)

        let four = session(exercises: 4)
        XCTAssertEqual(HomeCoachSectionPresenter.previewExercises(four).count, 4)
        XCTAssertEqual(HomeCoachSectionPresenter.additionalExerciseCount(four), 0)
    }

    func testPreviewExerciseCarriesLoadSetsAndReps() {
        let preview = HomeCoachSectionPresenter.previewExercises(session()).first
        XCTAssertEqual(preview?.name, "Exercise 0")
        XCTAssertEqual(preview?.loadKg, 40)
        XCTAssertEqual(preview?.sets, 3)
        XCTAssertEqual(preview?.repsText, "8–12")
    }

    func testWhyFallsBackWhenTheSessionHasNoSubtitle() {
        let blocks = HomeCoachSectionPresenter.blocks(suggestions: [],
                                                       recommendation: session(subtitle: ""),
                                                       expanded: false)
        guard case let .suggestedWorkout(_, why, _) = blocks.last else {
            return XCTFail("Expected a suggested workout block")
        }
        XCTAssertEqual(why, HomeCoachSectionPresenter.fallbackWhy)
    }

    func testToneRoleMapsPositiveWarningNeutral() {
        XCTAssertEqual(HomeCoachSectionPresenter.toneRole(.positive), .positive)
        XCTAssertEqual(HomeCoachSectionPresenter.toneRole(.warning), .warning)
        XCTAssertEqual(HomeCoachSectionPresenter.toneRole(.neutral), .neutral)
    }
}
