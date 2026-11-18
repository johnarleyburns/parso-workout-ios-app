import Foundation
import Testing
@testable import CadenceCore

struct CoachSchedulePreferencesCodableTests {

    // MARK: - Legacy blob: missing tracked groups AND dailyStepTarget

    @Test func legacyBlobMissingTrackedGroupsAndDailyStepTarget() throws {
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

        if case .fixed(let days) = prefs.restPreference {
            let sorted = days.sorted(by: { $0.rawValue < $1.rawValue })
            #expect(sorted == [.monday, .friday], "Legacy rest pattern should survive (days 2,6 = Mon,Fri)")
        } else {
            Issue.record("Expected fixed rest preference from legacy blob")
        }
        #expect(prefs.allowsTwoADays, "Legacy two-a-days should survive")
        #expect(prefs.sameDayCardioTiming == .separateLater, "Legacy cardio timing should survive")

        // Missing keys fall back to defaults.
        #expect(prefs.dailyStepTarget == 8_000, "Missing dailyStepTarget should default to 8000")
        #expect(prefs.trackedMuscleGroups == MuscleGroup.defaultTracked, "A blob with no coverage keys at all should track the defaults")
        #expect(prefs.desiredSetsPerExercise == 3, "Missing desiredSetsPerExercise should default to 3")
    }

    // MARK: - Legacy blob: missing only coverage opt-outs (had dailyStepTarget before the new field)

    @Test func legacyBlobMissingOnlyCoverageOptOuts() throws {
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

        if case .rolling(let n) = prefs.restPreference {
            #expect(n == 4)
        } else {
            Issue.record("Expected rolling rest preference")
        }
        #expect(prefs.allowsTwoADays, "retired setting is always on")
        #expect(prefs.sameDayCardioTiming == .afterStrength)
        #expect(prefs.dailyStepTarget == 12_000, "Existing dailyStepTarget should survive")
        #expect(prefs.trackedMuscleGroups == MuscleGroup.defaultTracked, "A blob with no coverage keys at all should track the defaults")
        #expect(prefs.desiredSetsPerExercise == 3, "Missing desiredSetsPerExercise should default to 3")
    }

    // MARK: - Pre-DB++ coverage opt-outs fold into the tracked set

    /// Before the DB++ migration a user switched coverage off per 8-case body part.
    /// `BodyPart` is gone, but an old store must not silently start nagging about a
    /// group the user had turned off — every group under an excluded part drops out
    /// of `trackedMuscleGroups` on decode.
    @Test func legacyExcludedCoveragePartsFoldIntoTrackedGroups() throws {
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

        #expect(!prefs.trackedMuscleGroups.contains(.abdominals), "An excluded 'abs' opt-out must keep abdominals untracked")
        #expect(!prefs.trackedMuscleGroups.contains(.calves), "An excluded 'calves' opt-out must keep calves untracked")
        #expect(prefs.trackedMuscleGroups.contains(.chest), "Groups the user never excluded stay tracked")
        #expect(prefs.trackedMuscleGroups.contains(.quadriceps), "Groups the user never excluded stay tracked")
    }

    /// The retired key is decode-only: re-encoding must not resurrect a vocabulary
    /// the app no longer has.
    @Test func legacyExcludedCoveragePartsIsNotWrittenBack() throws {
        let prefs = CoachSchedulePreferences(trackedMuscleGroups: [.chest, .lats])
        let data = try JSONEncoder().encode(prefs)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(!json.contains("excludedCoverageParts"), "The retired BodyPart key must never be encoded again")
    }

    @Test func versionTwoPreferencesGainSpecializedGroupsOnce() throws {
        let data = try JSONEncoder().encode(CoachSchedulePreferences(trackedMuscleGroups: [.chest]))
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["trackedMuscleGroupsVersion"] = 2
        let oldData = try JSONSerialization.data(withJSONObject: json)
        let migrated = try JSONDecoder().decode(CoachSchedulePreferences.self, from: oldData)
        #expect(migrated.trackedMuscleGroups == [.chest, .hipFlexors, .tibialis, .neck, .rotatorCuff])
        var customized = migrated
        customized.trackedMuscleGroups.remove(.neck)
        let roundTrip = try JSONDecoder().decode(CoachSchedulePreferences.self,
            from: JSONEncoder().encode(customized))
        #expect(!roundTrip.trackedMuscleGroups.contains(.neck))
    }

    // MARK: - Round-trip stability

    @Test func roundTripStable() throws {
        let prefs = CoachSchedulePreferences(
            restPreference: .fixed(days: [.saturday, .sunday]),
            allowsTwoADays: true,
            sameDayCardioTiming: .separateLater,
            dailyStepTarget: 10_000,
            desiredSetsPerExercise: 4,
            trackedMuscleGroups: [.abdominals, .calves]
        )
        let data = try JSONEncoder().encode(prefs)
        let decoded = try JSONDecoder().decode(CoachSchedulePreferences.self, from: data)

        #expect(decoded.restPreference == .fixed(days: [.saturday, .sunday]))
        #expect(decoded.allowsTwoADays)
        #expect(decoded.sameDayCardioTiming == .separateLater)
        #expect(decoded.dailyStepTarget == 10_000)
        #expect(decoded.trackedMuscleGroups == [.abdominals, .calves])
        #expect(decoded.desiredSetsPerExercise == 4)
    }

    // MARK: - Clamping still applies through decoder

    @Test func decodingAppliesClamping() throws {
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

        #expect(prefs.dailyStepTarget == 2_000, "Step target below 2_000 should clamp to 2_000")
        #expect(prefs.desiredSetsPerExercise == 4, "Desired sets above 4 should clamp to 4")
    }

    // MARK: - Retired day-per-week targets

    /// Old stores and exports carried strength/cardio days-per-week targets. They
    /// must decode (unknown keys ignored) and never be written back.
    @Test func retiredDayTargetKeysDecodeButAreNeverEncoded() throws {
        let legacyJSON = """
        {
          "strengthDaysPerWeek": 4,
          "cardioDaysPerWeek": 6,
          "restPreference": {"rolling": {"everyNDays": 3}},
          "allowsTwoADays": true
        }
        """
        let prefs = try JSONDecoder().decode(CoachSchedulePreferences.self,
                                             from: Data(legacyJSON.utf8))
        #expect(prefs.allowsTwoADays)
        let json = try #require(String(data: JSONEncoder().encode(prefs), encoding: .utf8))
        #expect(!json.contains("DaysPerWeek"))
        #expect(!json.contains("stepGoal"))
    }

    // MARK: - trackedMuscleGroups survives as a populated set

    @Test func trackedMuscleGroupsSurvivesPopulatedSet() throws {
        let prefs = CoachSchedulePreferences(
            trackedMuscleGroups: [.abdominals, .calves, .biceps]
        )
        let data = try JSONEncoder().encode(prefs)
        let decoded = try JSONDecoder().decode(CoachSchedulePreferences.self, from: data)

        #expect(decoded.trackedMuscleGroups == [.abdominals, .calves, .biceps])
    }

    @Test func legacyExplicitTrackedGroupsReceiveNewDBPPVolumeGroupsOnce() throws {
        // This is the pre-v2 set used by existing installs. The migration adds
        // groups now present in DB++'s planning ontology, then persists v2 so a
        // deliberately customized set remains stable on future reads.
        let legacyJSON = """
        {
          "strengthDaysPerWeek": 3,
          "cardioDaysPerWeek": 2,
          "restPreference": {"rolling": {"everyNDays": 3}},
          "allowsTwoADays": false,
          "sameDayCardioTiming": "afterStrength",
          "dailyStepTarget": 8000,
          "desiredSetsPerExercise": 3,
          "trackedMuscleGroups": [
            "abdominals", "biceps", "calves", "chest", "forearms", "glutes",
            "hamstrings", "lats", "middle_back", "quadriceps", "shoulders",
            "traps", "triceps"
          ]
        }
        """
        let decoded = try JSONDecoder().decode(
            CoachSchedulePreferences.self,
            from: Data(legacyJSON.utf8)
        )

        #expect(decoded.trackedMuscleGroups.contains(.abductors))
        #expect(decoded.trackedMuscleGroups.contains(.adductors))
        #expect(decoded.trackedMuscleGroups.contains(.lowerBack))

        let reencoded = try JSONEncoder().encode(decoded)
        let roundTrip = try JSONDecoder().decode(
            CoachSchedulePreferences.self,
            from: reencoded
        )
        #expect(roundTrip.trackedMuscleGroups == decoded.trackedMuscleGroups)
    }

    // MARK: - CoachPreferenceProfile: defensive decoder

    @Test func coachPreferenceProfileDecodesWithMissingFields() throws {
        let legacyJSON = """
        {
          "version": 2
        }
        """
        let data = Data(legacyJSON.utf8)
        let profile = try JSONDecoder().decode(CoachPreferenceProfile.self, from: data)

        #expect(profile.version == 2)
        #expect(profile.aerobicPreferences.count == 0)
        #expect(profile.strengthPreferences.count == 0)
        #expect(profile.avoidedTags.count == 0)
        #expect(profile.selectionEvents.count == 0)
    }

    @Test func coachPreferenceProfileRoundTripStable() throws {
        var profile = CoachPreferenceProfile.empty
        profile.version = 3
        profile.avoidedTags = ["anaerobic", "threshold"]
        profile.aerobicPreferences = [
            AerobicPreference(intent: .moderateAerobic, modality: .cycle, score: 5,
                              updatedAt: Date(timeIntervalSince1970: 1_750_000_000))
        ]

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(CoachPreferenceProfile.self, from: data)

        #expect(decoded.version == 3)
        #expect(decoded.avoidedTags == ["anaerobic", "threshold"])
        #expect(decoded.aerobicPreferences.count == 1)
        #expect(decoded.aerobicPreferences.first?.score == 5)
    }
}

// Retired planner day targets: the public surface must not carry them.
struct RetiredDayTargetSurfaceTests {
    @Test func noPublicModelEncodesRetiredGoalKeys() throws {
        let retired = ["strengthDaysPerWeek", "cardioDaysPerWeek", "stepGoal", "weeklyCardioMinutesGoal"]
        let blobs: [Data] = [
            try JSONEncoder().encode(CoachSchedulePreferences.default),
            try JSONEncoder().encode(ExportPreferences(schedulePreferences: .default)),
            try JSONEncoder().encode(WorkoutSettings.default),
        ]
        for data in blobs {
            let json = try #require(String(data: data, encoding: .utf8))
            for key in retired { #expect(!json.contains(key), "\(key) leaked into \(json)") }
        }
    }

    @Test func recommendationsDoNotDeriveFromLegacyDayTargets() throws {
        func prefs(_ extra: String) throws -> CoachSchedulePreferences {
            try JSONDecoder().decode(CoachSchedulePreferences.self,
                                     from: Data("{\(extra)\"allowsTwoADays\": false}".utf8))
        }
        let facts = CoachFacts.make(from: [], goal: .strength, experience: .intermediate,
                                    now: Date(timeIntervalSince1970: 1_760_000_000))
        let low = try prefs("\"strengthDaysPerWeek\": 2, \"cardioDaysPerWeek\": 0,")
        let high = try prefs("\"strengthDaysPerWeek\": 5, \"cardioDaysPerWeek\": 7,")
        #expect(low == high, "Legacy day-target keys must be ignored on decode")
        let a = CoachDecisionEngine.run(facts, schedulePreferences: low)
        let b = CoachDecisionEngine.run(facts, schedulePreferences: high)
        #expect(a.primary.id == b.primary.id)
    }
}
