import XCTest
@testable import CadenceFeatures
import CadenceCore

final class WatchSyncTests: XCTestCase {

    // MARK: - WeightIncrement

    func testPoundChips() {
        let inc = WeightIncrement(unit: .pounds)
        XCTAssertEqual(inc.chips, [-5, 5])
        XCTAssertEqual(inc.crownDetent, 2.5)
        XCTAssertEqual(inc.range, 0...650)
    }

    func testKilogramChips() {
        let inc = WeightIncrement(unit: .kilograms)
        XCTAssertEqual(inc.chips, [-2.5, 2.5])
        XCTAssertEqual(inc.crownDetent, 1.25)
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

    func testContextAppliesAllFourSettings() {
        var prefs = WatchSync.Preferences()
        prefs = prefs.applying(context: [
            "settings.unit": "pounds",
            "settings.intervalColorBlind": true,
            "settings.restSeconds": 120,
            "settings.cooldownMinutes": 3,
        ])
        XCTAssertEqual(prefs.unit, .pounds)
        XCTAssertTrue(prefs.intervalColorBlind)
        XCTAssertEqual(prefs.restSeconds, 120)
        XCTAssertEqual(prefs.cooldownMinutes, 3)
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
        let prefs = WatchSync.Preferences(unit: .pounds, intervalColorBlind: true, restSeconds: 60, cooldownMinutes: 3, recentPartnerNames: ["Jo"])
        let dict = WatchSync.Preferences.contextDict(prefs)
        let restored = WatchSync.Preferences().applying(context: dict)
        XCTAssertEqual(restored.unit, prefs.unit)
        XCTAssertEqual(restored.intervalColorBlind, prefs.intervalColorBlind)
        XCTAssertEqual(restored.restSeconds, prefs.restSeconds)
        XCTAssertEqual(restored.cooldownMinutes, prefs.cooldownMinutes)
        XCTAssertEqual(restored.recentPartnerNames, prefs.recentPartnerNames)
    }

    func testMissingKeysPreserveDefaults() {
        var prefs = WatchSync.Preferences(unit: .pounds, restSeconds: 90)
        prefs = prefs.applying(context: [:])
        XCTAssertEqual(prefs.unit, .pounds)
        XCTAssertEqual(prefs.restSeconds, 90)
    }

    func testInvalidUnitPreservesExisting() {
        var prefs = WatchSync.Preferences(unit: .kilograms)
        prefs = prefs.applying(context: ["settings.unit": "stones"])
        XCTAssertEqual(prefs.unit, .kilograms)
    }
}
