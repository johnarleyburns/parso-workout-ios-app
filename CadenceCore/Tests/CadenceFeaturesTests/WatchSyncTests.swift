import XCTest
@testable import CadenceFeatures
import CadenceCore

final class WatchSyncTests: XCTestCase {

    // MARK: - WeightIncrement

    func testPoundChips() {
        let inc = WeightIncrement(unit: .pounds)
        XCTAssertEqual(inc.negativeChips, [-45, -35, -25, -10, -5, -2.5])
        XCTAssertEqual(inc.positiveChips, [45, 35, 25, 10, 5, 2.5])
        XCTAssertEqual(inc.chips, [-45, -35, -25, -10, -5, -2.5, 45, 35, 25, 10, 5, 2.5])
        XCTAssertEqual(inc.crownDetent, 2.5)
        XCTAssertEqual(inc.range, 0...650)
    }

    func testChipLabel_formatsHalfIncrements() {
        let inc = WeightIncrement(unit: .pounds)
        XCTAssertEqual(inc.chipLabel(-2.5), "-2.5")
        XCTAssertEqual(inc.chipLabel(2.5), "+2.5")
        XCTAssertEqual(inc.chipLabel(5), "+5")
        XCTAssertEqual(inc.chipLabel(-10), "-10")
    }

    func testKilogramChips() {
        let inc = WeightIncrement(unit: .kilograms)
        XCTAssertEqual(inc.negativeChips, [-25, -20, -15, -10, -5, -2.5])
        XCTAssertEqual(inc.positiveChips, [25, 20, 15, 10, 5, 2.5])
        XCTAssertEqual(inc.chips, [-25, -20, -15, -10, -5, -2.5, 25, 20, 15, 10, 5, 2.5])
        XCTAssertEqual(inc.crownDetent, 2.5)
        XCTAssertEqual(inc.range, 0...300)
    }

    func testLocaleDefaultUS() {
        let locale = Locale(identifier: "en_US")
        let result = locale.measurementSystem == .us ? MeasurementUnitPreference.pounds : .kilograms
        XCTAssertEqual(WeightIncrement.unitDefault(), result)
    }

    // MARK: - Context apply

    func testContextAppliesUnit() {
        var prefs = WatchSync.Preferences(unit: .kilograms)
        prefs = prefs.applying(context: ["settings.unit": "pounds"])
        XCTAssertEqual(prefs.unit, .pounds)
    }

    func testContextAppliesAllSettings() {
        var prefs = WatchSync.Preferences()
        prefs = prefs.applying(context: [
            "settings.unit": "pounds",
            "settings.distanceUnit": "miles",
            "settings.intervalColorBlind": true,
            "settings.restSeconds": 120,
            "settings.warmupMinutes": 4,
            "settings.cooldownMinutes": 3,
            "settings.workoutSounds": false,
        ])
        XCTAssertEqual(prefs.unit, .pounds)
        XCTAssertEqual(prefs.distanceUnit, .miles)
        XCTAssertTrue(prefs.intervalColorBlind)
        XCTAssertEqual(prefs.restSeconds, 120)
        XCTAssertEqual(prefs.warmupMinutes, 4)
        XCTAssertEqual(prefs.cooldownMinutes, 3)
        XCTAssertFalse(prefs.workoutSounds)
    }

    func testContextAppliesDistanceUnit() {
        var prefs = WatchSync.Preferences(distanceUnit: .kilometers)
        prefs = prefs.applying(context: ["settings.distanceUnit": "miles"])
        XCTAssertEqual(prefs.distanceUnit, .miles)
    }

    func testContextAppliesRecentPartners() {
        var prefs = WatchSync.Preferences()
        prefs = prefs.applying(context: [
            "partners.recent": ["Jo", "Sam"],
        ])
        XCTAssertEqual(prefs.recentPartnerNames, ["Jo", "Sam"])
    }

    func testContextIgnoresUnknownKeys() {
        var prefs = WatchSync.Preferences(unit: .kilograms)
        prefs = prefs.applying(context: ["unknown": 1])
        XCTAssertEqual(prefs.unit, .kilograms)
    }

    func testContextDictRoundTrip() {
        let prefs = WatchSync.Preferences(unit: .pounds, distanceUnit: .miles, intervalColorBlind: true, restSeconds: 60, warmupMinutes: 4, cooldownMinutes: 3, workoutSounds: false, recentPartnerNames: ["Jo"])
        let dict = WatchSync.Preferences.contextDict(prefs)
        let restored = WatchSync.Preferences().applying(context: dict)
        XCTAssertEqual(restored.unit, prefs.unit)
        XCTAssertEqual(restored.distanceUnit, prefs.distanceUnit)
        XCTAssertEqual(restored.intervalColorBlind, prefs.intervalColorBlind)
        XCTAssertEqual(restored.restSeconds, prefs.restSeconds)
        XCTAssertEqual(restored.warmupMinutes, prefs.warmupMinutes)
        XCTAssertEqual(restored.cooldownMinutes, prefs.cooldownMinutes)
        XCTAssertEqual(restored.workoutSounds, prefs.workoutSounds)
        XCTAssertEqual(restored.recentPartnerNames, prefs.recentPartnerNames)
    }

    func testContextDictAddsUpdatedAtWhenRequested() {
        let date = Date(timeIntervalSince1970: 1_234)
        let dict = WatchSync.Preferences.contextDict(WatchSync.Preferences(), updatedAt: date)
        XCTAssertEqual(dict[WatchSync.Key.contextUpdatedAt] as? Date, date)
    }

    func testMissingKeysPreserveDefaults() {
        var prefs = WatchSync.Preferences(unit: .pounds, restSeconds: 90, warmupMinutes: 2, cooldownMinutes: 4, workoutSounds: false)
        prefs = prefs.applying(context: [:])
        XCTAssertEqual(prefs.unit, .pounds)
        XCTAssertEqual(prefs.restSeconds, 90)
        XCTAssertEqual(prefs.warmupMinutes, 2)
        XCTAssertEqual(prefs.cooldownMinutes, 4)
        XCTAssertFalse(prefs.workoutSounds)
    }

    func testInvalidUnitPreservesExisting() {
        var prefs = WatchSync.Preferences(unit: .kilograms)
        prefs = prefs.applying(context: ["settings.unit": "stones"])
        XCTAssertEqual(prefs.unit, .kilograms)
    }

    func testInvalidDistanceUnitPreservesExisting() {
        var prefs = WatchSync.Preferences(distanceUnit: .kilometers)
        prefs = prefs.applying(context: ["settings.distanceUnit": "parsecs"])
        XCTAssertEqual(prefs.distanceUnit, .kilometers)
    }

    func testMissingDistanceUnitPreservesDefaults() {
        var prefs = WatchSync.Preferences(distanceUnit: .miles)
        prefs = prefs.applying(context: [:])
        XCTAssertEqual(prefs.distanceUnit, .miles)
    }

    func testInvalidValuesPreserveExisting() {
        var prefs = WatchSync.Preferences(restSeconds: 90, warmupMinutes: 5, cooldownMinutes: 5, workoutSounds: true)
        prefs = prefs.applying(context: [
            "settings.restSeconds": "fast",
            "settings.warmupMinutes": "long",
            "settings.cooldownMinutes": false,
            "settings.workoutSounds": "yes",
        ])
        XCTAssertEqual(prefs.restSeconds, 90)
        XCTAssertEqual(prefs.warmupMinutes, 5)
        XCTAssertEqual(prefs.cooldownMinutes, 5)
        XCTAssertTrue(prefs.workoutSounds)
    }

    func testStatusHelpers() {
        let date = Date(timeIntervalSince1970: 1_234)
        XCTAssertTrue(WatchSync.Status.syncing(date).isInProgress)
        XCTAssertFalse(WatchSync.Status.synced(date).isInProgress)
        XCTAssertEqual(WatchSync.Status.synced(date).toastText, "Watch synced")
        XCTAssertEqual(WatchSync.requestSettingsSyncMessage()[WatchSync.Key.command] as? String, WatchSync.Key.requestSettingsSync)
    }

    func testTodayPlanContextRoundTripStrengthAndCardio() {
        let updatedAt = Date(timeIntervalSince1970: 42)
        let plan = WatchSync.TodayPlan(sessions: [
            .init(id: "strength", kind: .strength, label: "Strength",
                  exerciseNames: ["Bench Press", "Back Squat"], repLadder: [12, 10, 8]),
            .init(id: "cardio", kind: .cardio, label: "Moderate aerobic",
                  cardioType: "run", durationMinutes: 30, zone: 2),
        ], updatedAt: updatedAt)

        let dict = WatchSync.TodayPlan.contextDict(plan)
        let restored = WatchSync.TodayPlan.from(context: dict)

        XCTAssertEqual(restored, plan)
        XCTAssertEqual(restored?.strengthSessions.first?.exerciseNames, ["Bench Press", "Back Squat"])
        XCTAssertFalse(restored?.isRestDay ?? true)
    }

    func testTodayPlanFromWeeklyRestDay() {
        let day = WeeklyPlan.DayOutline(date: Date(), label: "Rest", sessions: [
            PlannedSession(id: "rest", kind: .rest, label: "Rest", isHard: false, isRest: true)
        ], isToday: true)

        let plan = WatchSync.TodayPlan.from(day: day)

        XCTAssertTrue(plan.isRestDay)
        XCTAssertEqual(plan.sessions.first?.kind, .rest)
    }

    func testTodayPlanFromWeeklyStrengthUsesExercisePrescription() {
        let exercise = CoachSession.RecommendedExercise(
            name: "Bench Press",
            sets: 3,
            repsLow: 8,
            repsHigh: 12,
            rir: 2,
            repLadder: [12, 10, 8]
        )
        let day = WeeklyPlan.DayOutline(date: Date(), label: "Strength", sessions: [
            PlannedSession(id: "strength", kind: .strength, label: "Strength",
                           isHard: true, isRest: false, exercises: [exercise])
        ], isToday: true)

        let plan = WatchSync.TodayPlan.from(day: day)

        XCTAssertEqual(plan.strengthSessions.first?.exerciseNames, ["Bench Press"])
        XCTAssertEqual(plan.strengthSessions.first?.repLadder, [12, 10, 8])
    }
}
