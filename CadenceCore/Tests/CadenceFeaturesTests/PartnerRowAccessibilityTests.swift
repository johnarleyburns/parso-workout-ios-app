import Testing
import CadencePhoneFeatures
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

struct PartnerRowAccessibilityTests {
    @Test func unselectedRowSemantics() {
        let row = PartnerRowAccessibility(name: "Alex", isSelected: false)
        #expect(row.label == "Alex")
        #expect(row.value == "Not selected")
        #expect(!row.hasSelectedTrait)
        #expect(row.hint.contains("add Alex"))
    }

    @Test func selectedRowSemantics() {
        let row = PartnerRowAccessibility(name: "Alex", isSelected: true)
        #expect(row.value == "Selected")
        #expect(row.hasSelectedTrait)
        #expect(row.hint.contains("remove Alex"))
    }

    @Test func activationTogglesTwiceAndIdentifierIsStable() {
        let row = PartnerRowAccessibility(name: "Alex", isSelected: false)
        #expect(row.toggled.isSelected)
        #expect(row.toggled.toggled == row)
        #expect(row.identifier == "editor.partner.Alex")
        #expect(row.toggled.identifier == row.identifier)
    }
}
