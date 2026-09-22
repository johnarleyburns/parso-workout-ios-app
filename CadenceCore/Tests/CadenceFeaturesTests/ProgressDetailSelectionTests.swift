import XCTest
@testable import CadenceFeatures

final class ProgressDetailSelectionTests: XCTestCase {
    func testSelectingAnotherDisclosureCollapsesThePreviousOne() {
        var selection = ProgressDetailSelection()

        selection.toggle(.tests)
        XCTAssertEqual(selection.selected, .tests)

        selection.toggle(.trends)
        XCTAssertEqual(selection.selected, .trends)
    }

    func testTogglingTheOpenDisclosureCollapsesAllDetails() {
        var selection = ProgressDetailSelection(selected: .intensity)

        selection.toggle(.intensity)

        XCTAssertNil(selection.selected)
    }
}
