import XCTest
@testable import CadenceFeatures

final class PartnerRowAccessibilityTests: XCTestCase {
    func testUnselectedRowSemantics() {
        let row = PartnerRowAccessibility(name: "Alex", isSelected: false)
        XCTAssertEqual(row.label, "Alex")
        XCTAssertEqual(row.value, "Not selected")
        XCTAssertFalse(row.hasSelectedTrait)
        XCTAssertTrue(row.hint.contains("add Alex"))
    }

    func testSelectedRowSemantics() {
        let row = PartnerRowAccessibility(name: "Alex", isSelected: true)
        XCTAssertEqual(row.value, "Selected")
        XCTAssertTrue(row.hasSelectedTrait)
        XCTAssertTrue(row.hint.contains("remove Alex"))
    }

    func testActivationTogglesTwiceAndIdentifierIsStable() {
        let row = PartnerRowAccessibility(name: "Alex", isSelected: false)
        XCTAssertTrue(row.toggled.isSelected)
        XCTAssertEqual(row.toggled.toggled, row)
        XCTAssertEqual(row.identifier, "editor.partner.Alex")
        XCTAssertEqual(row.toggled.identifier, row.identifier)
    }
}
