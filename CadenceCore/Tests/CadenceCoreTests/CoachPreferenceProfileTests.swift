import XCTest
@testable import CadenceCore

final class CoachPreferenceProfileTests: XCTestCase {

    func testRecordAerobicSelectionIncrementsPreference() {
        var profile = CoachPreferenceProfile.empty
        let session = CoachSession(
            id: "aerobic.moderateCycle",
            kind: .moderateAerobic,
            title: "Steady cycle",
            durationMinutes: 35,
            modality: .cycle,
            intensity: .moderate,
            launchPayload: .cardio(type: "cycle", durationMinutes: 35)
        )
        let alternatives: [CoachSession] = [
            CoachSession(id: "aerobic.moderateRun", kind: .moderateAerobic, title: "Steady run",
                          durationMinutes: 25, modality: .run, intensity: .moderate,
                          launchPayload: .cardio(type: "run", durationMinutes: 25)),
        ]

        profile.recordSelection(session, from: alternatives, at: Date())

        XCTAssertEqual(profile.selectionEvents.count, 1)
        XCTAssertEqual(profile.aerobicPreferences.count, 1)
        XCTAssertEqual(profile.aerobicPreferences.first?.modality, .cycle)
        XCTAssertEqual(profile.aerobicPreferences.first?.intent, .moderateAerobic)
        XCTAssertEqual(profile.aerobicPreferences.first?.score, 1)
    }

    func testRecentRepeatedSelectionOutranksOlderSelection() {
        var profile = CoachPreferenceProfile.empty
        let now = Date()
        let older = now.addingTimeInterval(-3600)

        let cycleSession = CoachSession(
            id: "aerobic.moderateCycle", kind: .moderateAerobic,
            title: "Steady cycle", durationMinutes: 35,
            modality: .cycle, intensity: .moderate,
            launchPayload: .cardio(type: "cycle", durationMinutes: 35)
        )
        let runSession = CoachSession(
            id: "aerobic.moderateRun", kind: .moderateAerobic,
            title: "Steady run", durationMinutes: 25,
            modality: .run, intensity: .moderate,
            launchPayload: .cardio(type: "run", durationMinutes: 25)
        )

        profile.recordSelection(cycleSession, from: [], at: older)
        profile.recordSelection(cycleSession, from: [], at: now)

        XCTAssertEqual(profile.aerobicPreferences.first { $0.modality == .cycle }?.score, 2)
        let cyclePref = profile.aerobicPreferences.first { $0.modality == .cycle }
        let runPref = profile.aerobicPreferences.first { $0.modality == .run }
        XCTAssertNil(runPref)
        XCTAssertNotNil(cyclePref)
    }

    func testStrengthPreferenceIsScopedToMovementPattern() {
        var profile = CoachPreferenceProfile.empty
        let session = CoachSession(
            id: "strength.general", kind: .strength,
            title: "Strength", durationMinutes: 45,
            exercises: [
                CoachSession.RecommendedExercise(
                    name: "Back Squat", primaryMuscles: ["quadriceps", "glutes"],
                    sets: 3, repsLow: 6, repsHigh: 10, rir: 3
                )
            ],
            launchPayload: .strengthPlan("fullBody")
        )

        profile.recordSelection(session, from: [], at: Date())

        XCTAssertEqual(profile.strengthPreferences.count, 1)
        XCTAssertEqual(profile.strengthPreferences.first?.exerciseName, "Back Squat")
        XCTAssertEqual(profile.strengthPreferences.first?.pattern, .squat)
    }

    func testProfileCodableRoundTrip() throws {
        var profile = CoachPreferenceProfile.empty
        let session = CoachSession(
            id: "aerobic.moderateCycle", kind: .moderateAerobic,
            title: "Steady cycle", durationMinutes: 35,
            modality: .cycle, intensity: .moderate,
            launchPayload: .cardio(type: "cycle", durationMinutes: 35)
        )
        profile.recordSelection(session, from: [], at: Date(timeIntervalSince1970: 1_750_000_000))

        let encoded = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(CoachPreferenceProfile.self, from: encoded)

        XCTAssertEqual(decoded.version, profile.version)
        XCTAssertEqual(decoded.aerobicPreferences.count, profile.aerobicPreferences.count)
        XCTAssertEqual(decoded.aerobicPreferences.first?.modality, .cycle)
        XCTAssertEqual(decoded.selectionEvents.count, 1)
    }
}
