import XCTest
@testable import CadenceFeatures

final class WeeklyDetailSelectionTests: XCTestCase {
    func testOnlyOneWeeklyDetailCanBeSelected() {
        var selection = WeeklyDetailSelection()

        selection.toggle(.strength)
        XCTAssertEqual(selection.selected, .strength)

        selection.toggle(.cardio)
        XCTAssertEqual(selection.selected, .cardio)

        selection.toggle(.volume)
        XCTAssertEqual(selection.selected, .volume)
    }

    func testSelectingAWeeklyDetailReplacesTheCurrentSelectionWithoutTogglingItOff() {
        var selection = WeeklyDetailSelection(selected: .volume)

        selection.select(.cardio)
        XCTAssertEqual(selection.selected, .cardio)

        selection.select(.cardio)
        XCTAssertEqual(selection.selected, .cardio)
    }

    func testTogglingSelectedWeeklyDetailCollapsesAllDetails() {
        var selection = WeeklyDetailSelection(selected: .volume)

        selection.toggle(.volume)

        XCTAssertNil(selection.selected)
    }
}
