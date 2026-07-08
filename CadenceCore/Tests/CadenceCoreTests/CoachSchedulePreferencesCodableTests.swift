import XCTest
@testable import CadenceCore

final class CoachSchedulePreferencesCodableTests: XCTestCase {

    // MARK: - Legacy blob: missing excludedCoverageParts AND dailyStepTarget

    func testLegacyBlobMissingExcludedCoveragePartsAndDailyStepTarget() throws {
        let legacyJSON = """
        {
          "strengthDaysPerWeek": 4,
          "cardioDaysPerWeek": 2,
          "restPreference": {"fixed": {"days": [2, 6]}},
          "allowsTwoADays": true,
          "sameDayCardioTiming": "separateLater"
        }
        """
        let data = Data(legacyJSON.utf8)
        let prefs = try JSONDecoder().decode(CoachSchedulePreferences.self, from: data)

        XCTAssertEqual(prefs.strengthDaysPerWeek, 4,
                       "Legacy strength days should survive")
        XCTAssertEqual(prefs.cardioDaysPerWeek, 2,
                       "Legacy cardio days should survive")
        if case .fixed(let days) = prefs.restPreference {
            let sorted = days.sorted(by: { $0.rawValue < $1.rawValue })
            XCTAssertEqual(sorted, [.monday, .friday],
                           "Legacy rest pattern should survive (days 2,6 = Mon,Fri)")
        } else {
            XCTFail("Expected fixed rest preference from legacy blob")
        }
        XCTAssertTrue(prefs.allowsTwoADays,
                      "Legacy two-a-days should survive")
        XCTAssertEqual(prefs.sameDayCardioTiming, .separateLater,
                       "Legacy cardio timing should survive")

        // Missing keys fall back to defaults.
        XCTAssertEqual(prefs.dailyStepTarget, 8_000,
                       "Missing dailyStepTarget should default to 8000")
        XCTAssertEqual(prefs.excludedCoverageParts, [],
                       "Missing excludedCoverageParts should default to empty set")
    }

    // MARK: - Legacy blob: missing only excludedCoverageParts (had dailyStepTarget before the new field)

    func testLegacyBlobMissingOnlyExcludedCoverageParts() throws {
        let legacyJSON = """
        {
          "strengthDaysPerWeek": 3,
          "cardioDaysPerWeek": 5,
          "restPreference": {"rolling": {"everyNDays": 4}},
          "allowsTwoADays": false,
          "sameDayCardioTiming": "afterStrength",
          "dailyStepTarget": 12000
        }
        """
        let data = Data(legacyJSON.utf8)
        let prefs = try JSONDecoder().decode(CoachSchedulePreferences.self, from: data)

        XCTAssertEqual(prefs.strengthDaysPerWeek, 3)
        XCTAssertEqual(prefs.cardioDaysPerWeek, 5)
        if case .rolling(let n) = prefs.restPreference {
            XCTAssertEqual(n, 4)
        } else {
            XCTFail("Expected rolling rest preference")
        }
        XCTAssertFalse(prefs.allowsTwoADays)
        XCTAssertEqual(prefs.sameDayCardioTiming, .afterStrength)
        XCTAssertEqual(prefs.dailyStepTarget, 12_000,
                       "Existing dailyStepTarget should survive")
        XCTAssertEqual(prefs.excludedCoverageParts, [],
                       "Missing excludedCoverageParts should default to empty set")
    }

    // MARK: - Round-trip stability

    func testRoundTripStable() throws {
        let prefs = CoachSchedulePreferences(
            strengthDaysPerWeek: 4,
            cardioDaysPerWeek: 2,
            restPreference: .fixed(days: [.saturday, .sunday]),
            allowsTwoADays: true,
            sameDayCardioTiming: .separateLater,
            dailyStepTarget: 10_000,
            excludedCoverageParts: [.abs, .calves]
        )
        let data = try JSONEncoder().encode(prefs)
        let decoded = try JSONDecoder().decode(CoachSchedulePreferences.self, from: data)

        XCTAssertEqual(decoded.strengthDaysPerWeek, 4)
        XCTAssertEqual(decoded.cardioDaysPerWeek, 2)
        XCTAssertEqual(decoded.restPreference, .fixed(days: [.saturday, .sunday]))
        XCTAssertTrue(decoded.allowsTwoADays)
        XCTAssertEqual(decoded.sameDayCardioTiming, .separateLater)
        XCTAssertEqual(decoded.dailyStepTarget, 10_000)
        XCTAssertEqual(decoded.excludedCoverageParts, [.abs, .calves])
    }

    // MARK: - Clamping still applies through decoder

    func testDecodingAppliesClamping() throws {
        let json = """
        {
          "strengthDaysPerWeek": 1,
          "cardioDaysPerWeek": 10,
          "restPreference": {"rolling": {"everyNDays": 3}},
          "allowsTwoADays": false,
          "sameDayCardioTiming": "afterStrength",
          "dailyStepTarget": 1000,
          "excludedCoverageParts": []
        }
        """
        let data = Data(json.utf8)
        let prefs = try JSONDecoder().decode(CoachSchedulePreferences.self, from: data)

        XCTAssertEqual(prefs.strengthDaysPerWeek, 2,
                       "Strength below 2 should clamp to 2")
        XCTAssertEqual(prefs.cardioDaysPerWeek, 7,
                       "Cardio above 7 should clamp to 7")
        XCTAssertEqual(prefs.dailyStepTarget, 2_000,
                       "Step target below 2_000 should clamp to 2_000")
    }

    // MARK: - ExcludedCoverageParts survives as a populated set

    func testExcludedCoveragePartsSurvivesPopulatedSet() throws {
        let prefs = CoachSchedulePreferences(
            strengthDaysPerWeek: 3,
            excludedCoverageParts: [.abs, .calves, .biceps]
        )
        let data = try JSONEncoder().encode(prefs)
        let decoded = try JSONDecoder().decode(CoachSchedulePreferences.self, from: data)

        XCTAssertEqual(decoded.excludedCoverageParts, [.abs, .calves, .biceps])
        XCTAssertEqual(decoded.strengthDaysPerWeek, 3)
    }

    // MARK: - CoachPreferenceProfile: defensive decoder

    func testCoachPreferenceProfileDecodesWithMissingFields() throws {
        let legacyJSON = """
        {
          "version": 2
        }
        """
        let data = Data(legacyJSON.utf8)
        let profile = try JSONDecoder().decode(CoachPreferenceProfile.self, from: data)

        XCTAssertEqual(profile.version, 2)
        XCTAssertEqual(profile.aerobicPreferences.count, 0)
        XCTAssertEqual(profile.strengthPreferences.count, 0)
        XCTAssertEqual(profile.avoidedTags.count, 0)
        XCTAssertEqual(profile.selectionEvents.count, 0)
    }

    func testCoachPreferenceProfileRoundTripStable() throws {
        var profile = CoachPreferenceProfile.empty
        profile.version = 3
        profile.avoidedTags = ["anaerobic", "threshold"]
        profile.aerobicPreferences = [
            AerobicPreference(intent: .moderateAerobic, modality: .cycle, score: 5,
                              updatedAt: Date(timeIntervalSince1970: 1_750_000_000))
        ]

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(CoachPreferenceProfile.self, from: data)

        XCTAssertEqual(decoded.version, 3)
        XCTAssertEqual(decoded.avoidedTags, ["anaerobic", "threshold"])
        XCTAssertEqual(decoded.aerobicPreferences.count, 1)
        XCTAssertEqual(decoded.aerobicPreferences.first?.score, 5)
    }
}
