import XCTest
@testable import CadenceCore

final class CoachSchedulePreferencesCodableTests: XCTestCase {

    // MARK: - Legacy blob: missing tracked groups AND dailyStepTarget

    func testLegacyBlobMissingTrackedGroupsAndDailyStepTarget() throws {
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
        XCTAssertEqual(prefs.trackedMuscleGroups, MuscleGroup.defaultTracked,
                       "A blob with no coverage keys at all should track the defaults")
        XCTAssertEqual(prefs.desiredSetsPerExercise, 3,
                       "Missing desiredSetsPerExercise should default to 3")
    }

    // MARK: - Legacy blob: missing only coverage opt-outs (had dailyStepTarget before the new field)

    func testLegacyBlobMissingOnlyCoverageOptOuts() throws {
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
        XCTAssertEqual(prefs.trackedMuscleGroups, MuscleGroup.defaultTracked,
                       "A blob with no coverage keys at all should track the defaults")
        XCTAssertEqual(prefs.desiredSetsPerExercise, 3,
                       "Missing desiredSetsPerExercise should default to 3")
    }

    // MARK: - Pre-DB++ coverage opt-outs fold into the tracked set

    /// Before the DB++ migration a user switched coverage off per 8-case body part.
    /// `BodyPart` is gone, but an old store must not silently start nagging about a
    /// group the user had turned off — every group under an excluded part drops out
    /// of `trackedMuscleGroups` on decode.
    func testLegacyExcludedCoveragePartsFoldIntoTrackedGroups() throws {
        let legacyJSON = """
        {
          "strengthDaysPerWeek": 3,
          "cardioDaysPerWeek": 2,
          "restPreference": {"rolling": {"everyNDays": 3}},
          "allowsTwoADays": false,
          "sameDayCardioTiming": "afterStrength",
          "dailyStepTarget": 9000,
          "excludedCoverageParts": ["abs", "calves"]
        }
        """
        let prefs = try JSONDecoder().decode(CoachSchedulePreferences.self,
                                             from: Data(legacyJSON.utf8))

        XCTAssertFalse(prefs.trackedMuscleGroups.contains(.abdominals),
                       "An excluded 'abs' opt-out must keep abdominals untracked")
        XCTAssertFalse(prefs.trackedMuscleGroups.contains(.calves),
                       "An excluded 'calves' opt-out must keep calves untracked")
        XCTAssertTrue(prefs.trackedMuscleGroups.contains(.chest),
                      "Groups the user never excluded stay tracked")
        XCTAssertTrue(prefs.trackedMuscleGroups.contains(.quadriceps),
                      "Groups the user never excluded stay tracked")
    }

    /// The retired key is decode-only: re-encoding must not resurrect a vocabulary
    /// the app no longer has.
    func testLegacyExcludedCoveragePartsIsNotWrittenBack() throws {
        let prefs = CoachSchedulePreferences(trackedMuscleGroups: [.chest, .lats])
        let data = try JSONEncoder().encode(prefs)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(json.contains("excludedCoverageParts"),
                       "The retired BodyPart key must never be encoded again")
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
            desiredSetsPerExercise: 4,
            trackedMuscleGroups: [.abdominals, .calves]
        )
        let data = try JSONEncoder().encode(prefs)
        let decoded = try JSONDecoder().decode(CoachSchedulePreferences.self, from: data)

        XCTAssertEqual(decoded.strengthDaysPerWeek, 4)
        XCTAssertEqual(decoded.cardioDaysPerWeek, 2)
        XCTAssertEqual(decoded.restPreference, .fixed(days: [.saturday, .sunday]))
        XCTAssertTrue(decoded.allowsTwoADays)
        XCTAssertEqual(decoded.sameDayCardioTiming, .separateLater)
        XCTAssertEqual(decoded.dailyStepTarget, 10_000)
        XCTAssertEqual(decoded.trackedMuscleGroups, [.abdominals, .calves])
        XCTAssertEqual(decoded.desiredSetsPerExercise, 4)
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
          "excludedCoverageParts": [],
          "desiredSetsPerExercise": 9
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
        XCTAssertEqual(prefs.desiredSetsPerExercise, 4,
                       "Desired sets above 4 should clamp to 4")
    }

    // MARK: - trackedMuscleGroups survives as a populated set

    func testTrackedMuscleGroupsSurvivesPopulatedSet() throws {
        let prefs = CoachSchedulePreferences(
            strengthDaysPerWeek: 3,
            trackedMuscleGroups: [.abdominals, .calves, .biceps]
        )
        let data = try JSONEncoder().encode(prefs)
        let decoded = try JSONDecoder().decode(CoachSchedulePreferences.self, from: data)

        XCTAssertEqual(decoded.trackedMuscleGroups, [.abdominals, .calves, .biceps])
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
