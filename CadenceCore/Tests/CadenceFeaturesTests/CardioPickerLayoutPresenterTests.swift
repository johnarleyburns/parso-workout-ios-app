import XCTest
@testable import CadenceFeatures

/// Issue #619: the order of the Cardio picker's sections is a value-only
/// policy that `CardioPickerView` renders verbatim.
final class CardioPickerLayoutPresenterTests: XCTestCase {

    func testStartModeOrdersCreditThenSuggestionThenLabeledGrid() {
        XCTAssertEqual(
            CardioPickerLayoutPresenter.sections(for: .start, showsWeeklyCredit: true,
                                                 showsSuggestCardio: true),
            [.weeklyCredit, .suggestCardio, .excludedTypesNoteWhenPresent,
             .cardioSection, .typeGrid, .showMore])
    }

    func testScheduleModeHasNoCreditOrSuggestionAndKeepsItsGrid() {
        let sections = CardioPickerLayoutPresenter.sections(for: .schedule, showsWeeklyCredit: true,
                                                            showsSuggestCardio: true)
        XCTAssertEqual(sections, [.typeGrid, .showMore])
        XCTAssertFalse(sections.contains(.weeklyCredit))
        XCTAssertFalse(sections.contains(.suggestCardio))
        XCTAssertFalse(sections.contains(.excludedTypesNoteWhenPresent))
    }

    func testSuggestCardioAppearsExactlyOnceBeforeTheCardioSectionAndGrid() {
        let sections = CardioPickerLayoutPresenter.sections(for: .start, showsWeeklyCredit: true,
                                                            showsSuggestCardio: true)
        XCTAssertEqual(sections.filter { $0 == .suggestCardio }.count, 1)
        guard let suggest = sections.firstIndex(of: .suggestCardio),
              let credit = sections.firstIndex(of: .weeklyCredit),
              let heading = sections.firstIndex(of: .cardioSection),
              let grid = sections.firstIndex(of: .typeGrid),
              let showMore = sections.firstIndex(of: .showMore) else {
            return XCTFail("missing start-mode section in \(sections)")
        }
        XCTAssertEqual(credit, 0, "weekly credit is the first thing under the title")
        XCTAssertEqual(suggest, credit + 1, "Suggest Cardio sits directly below the credit ring")
        XCTAssertLessThan(suggest, heading)
        XCTAssertEqual(heading + 1, grid, "the Cardio heading is immediately before the grid")
        XCTAssertLessThan(grid, showMore)
        XCTAssertFalse(sections[heading...].contains(.suggestCardio), "never inside/after the grid")
    }

    func testExcludedTypesNoteTravelsWithTheSuggestionAction() {
        let sections = CardioPickerLayoutPresenter.sections(for: .start, showsWeeklyCredit: true,
                                                            showsSuggestCardio: true)
        let suggest = sections.firstIndex(of: .suggestCardio)
        let note = sections.firstIndex(of: .excludedTypesNoteWhenPresent)
        XCTAssertNotNil(suggest)
        XCTAssertEqual(note, suggest.map { $0 + 1 })

        let withoutSuggest = CardioPickerLayoutPresenter.sections(for: .start, showsWeeklyCredit: true,
                                                                  showsSuggestCardio: false)
        XCTAssertEqual(withoutSuggest, [.weeklyCredit, .cardioSection, .typeGrid, .showMore])
    }

    func testStartModeWithoutAnInjectedCreditOmitsOnlyTheRing() {
        XCTAssertEqual(
            CardioPickerLayoutPresenter.sections(for: .start, showsWeeklyCredit: false,
                                                 showsSuggestCardio: true),
            [.suggestCardio, .excludedTypesNoteWhenPresent, .cardioSection, .typeGrid, .showMore])
    }
}
