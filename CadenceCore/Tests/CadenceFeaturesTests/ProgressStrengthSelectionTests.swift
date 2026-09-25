import XCTest
@testable import CadenceFeatures

final class ProgressStrengthSelectionTests: XCTestCase {
    func testDefaultsUseCanonicalPowerLiftsAndCombined() {
        XCTAssertEqual(ProgressStrengthSelection().selectedNames,
                       ["Bench Press", "Barbell Squat", "Deadlift", "Combined"])
    }

    func testCustomSelectionPersistsAndRoundTrips() {
        let defaults = UserDefaults(suiteName: "ProgressStrengthSelectionTests.\(UUID().uuidString)")!
        let selection = ProgressStrengthSelection(selectedNames: ["Bench Press", "Overhead Press"])
        selection.persist(defaults: defaults)

        XCTAssertEqual(ProgressStrengthSelection.persisted(defaults: defaults), selection)
    }

    func testLegacySquatPreferenceMigratesToBarbellSquat() {
        let defaults = UserDefaults(suiteName: "ProgressStrengthSelectionTests.\(UUID().uuidString)")!
        defaults.set(try! JSONEncoder().encode(["Squat", "Deadlift"]),
                     forKey: ProgressStrengthSelection.persistenceKey)

        XCTAssertEqual(ProgressStrengthSelection.persisted(defaults: defaults).selectedNames,
                       ["Barbell Squat", "Deadlift"])
    }
}
