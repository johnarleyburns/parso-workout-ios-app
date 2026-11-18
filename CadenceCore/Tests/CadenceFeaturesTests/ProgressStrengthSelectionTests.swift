import Foundation
import Testing
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

struct ProgressStrengthSelectionTests {
    @Test func defaultsUseCanonicalPowerLiftsAndTotal() {
        #expect(ProgressStrengthSelection().selectedNames
                       == ["Bench Press", "Barbell Squat", "Deadlift", "Total"])
    }

    @Test func customSelectionPersistsAndRoundTrips() {
        let defaults = UserDefaults(suiteName: "ProgressStrengthSelectionTests.\(UUID().uuidString)")!
        let selection = ProgressStrengthSelection(selectedNames: ["Bench Press", "Overhead Press"])
        selection.persist(defaults: defaults)

        #expect(ProgressStrengthSelection.persisted(defaults: defaults) == selection)
    }

    @Test func legacySquatPreferenceMigratesToBarbellSquat() {
        let defaults = UserDefaults(suiteName: "ProgressStrengthSelectionTests.\(UUID().uuidString)")!
        defaults.set(try! JSONEncoder().encode(["Squat", "Deadlift"]),
                     forKey: ProgressStrengthSelection.persistenceKey)

        #expect(ProgressStrengthSelection.persisted(defaults: defaults).selectedNames
                       == ["Barbell Squat", "Deadlift"])
    }

    @Test func legacyCombinedPreferenceMigratesToTotal() {
        let defaults = UserDefaults(suiteName: "ProgressStrengthSelectionTests.\(UUID().uuidString)")!
        defaults.set(try! JSONEncoder().encode(["Bench Press", "Combined"]),
                     forKey: ProgressStrengthSelection.persistenceKey)

        #expect(ProgressStrengthSelection.persisted(defaults: defaults).selectedNames
                       == ["Bench Press", "Total"])
    }
}
