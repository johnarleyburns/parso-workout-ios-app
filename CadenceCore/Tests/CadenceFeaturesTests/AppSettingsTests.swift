import XCTest
import Foundation
import CadenceCore
import CadenceFeatures

/// AppSettings (the "SettingsStore" lift, test-pyramid Phase 2) is now headlessly
/// testable via its injected `UserDefaults`. Covers persistence, defaults, and the
/// lossless preferences round-trip (FR-6.2).
final class AppSettingsTests: XCTestCase {

    private func freshDefaults(_ name: String = #function) -> UserDefaults {
        let suite = "AppSettingsTests.\(name)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    func testDefaultsWhenEmpty() {
        let s = AppSettings(defaults: freshDefaults())
        XCTAssertEqual(s.unit, SettingsDefault.unit)
        XCTAssertEqual(s.formula, SettingsDefault.oneRepMaxFormula)
        XCTAssertEqual(s.restSeconds, SettingsDefault.restSeconds)
        XCTAssertFalse(s.hasCompletedOnboarding)
    }

    func testMutationPersistsAcrossInstances() {
        let d = freshDefaults()
        let a = AppSettings(defaults: d)
        a.unit = .pounds
        a.restSeconds = 120
        a.trainingGoal = .strength
        a.coachHidden = true

        let b = AppSettings(defaults: d)
        XCTAssertEqual(b.unit, .pounds)
        XCTAssertEqual(b.restSeconds, 120)
        XCTAssertEqual(b.trainingGoal, .strength)
        XCTAssertTrue(b.coachHidden)
    }

    func testFavoriteRoutineToggle() {
        let s = AppSettings(defaults: freshDefaults())
        XCTAssertFalse(s.isRoutineFavorite("ppl"))
        s.toggleFavoriteRoutine("ppl")
        XCTAssertTrue(s.isRoutineFavorite("ppl"))
        s.toggleFavoriteRoutine("ppl")
        XCTAssertFalse(s.isRoutineFavorite("ppl"))
    }

    func testCoachScheduleJSONPersistence() {
        let d = freshDefaults()
        let a = AppSettings(defaults: d)
        a.coachSchedulePreferences = CoachSchedulePreferences.default
            .withTwoADays(true)
            .withDesiredSetsPerExercise(4)
        let b = AppSettings(defaults: d)
        XCTAssertTrue(b.coachSchedulePreferences.allowsTwoADays)
        XCTAssertEqual(b.coachSchedulePreferences.desiredSetsPerExercise, 4)
    }

    func testExportImportRoundTrip() {
        let src = AppSettings(defaults: freshDefaults("src"))
        src.unit = .pounds
        src.weeklyCardioMinutesGoal = 200
        src.experienceLevel = .advanced
        src.userAge = 41
        src.warmupMinutes = 7
        src.coachSchedulePreferences = src.coachSchedulePreferences.withDesiredSetsPerExercise(4)
        let snapshot = src.exportPreferences()

        let dst = AppSettings(defaults: freshDefaults("dst"))
        dst.applyImportedPreferences(snapshot)
        XCTAssertEqual(dst.unit, .pounds)
        XCTAssertEqual(dst.weeklyCardioMinutesGoal, 200)
        XCTAssertEqual(dst.experienceLevel, .advanced)
        XCTAssertEqual(dst.userAge, 41)
        XCTAssertEqual(dst.warmupMinutes, 7)
        XCTAssertEqual(dst.coachSchedulePreferences.desiredSetsPerExercise, 4)
    }
}
