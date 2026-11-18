import Foundation
import Testing
@testable import CadenceCore

struct CoachPreferenceProfileTests {

    @Test func recordAerobicSelectionIncrementsPreference() {
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

        #expect(profile.selectionEvents.count == 1)
        #expect(profile.aerobicPreferences.count == 1)
        #expect(profile.aerobicPreferences.first?.modality == .cycle)
        #expect(profile.aerobicPreferences.first?.intent == .moderateAerobic)
        #expect(profile.aerobicPreferences.first?.score == 1)
    }

    @Test func recentRepeatedSelectionOutranksOlderSelection() {
        var profile = CoachPreferenceProfile.empty
        let now = Date()
        let older = now.addingTimeInterval(-3600)

        let cycleSession = CoachSession(
            id: "aerobic.moderateCycle", kind: .moderateAerobic,
            title: "Steady cycle", durationMinutes: 35,
            modality: .cycle, intensity: .moderate,
            launchPayload: .cardio(type: "cycle", durationMinutes: 35)
        )

        profile.recordSelection(cycleSession, from: [], at: older)
        profile.recordSelection(cycleSession, from: [], at: now)

        #expect(profile.aerobicPreferences.first { $0.modality == .cycle }?.score == 2)
        let cyclePref = profile.aerobicPreferences.first { $0.modality == .cycle }
        let runPref = profile.aerobicPreferences.first { $0.modality == .run }
        #expect(runPref == nil)
        #expect(cyclePref != nil)
    }

    @Test func strengthPreferenceIsScopedToMovementPattern() {
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

        #expect(profile.strengthPreferences.count == 1)
        #expect(profile.strengthPreferences.first?.exerciseName == "Back Squat")
        #expect(profile.strengthPreferences.first?.pattern == .squat)
    }

    @Test func profileCodableRoundTrip() throws {
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

        #expect(decoded.version == profile.version)
        #expect(decoded.aerobicPreferences.count == profile.aerobicPreferences.count)
        #expect(decoded.aerobicPreferences.first?.modality == .cycle)
        #expect(decoded.selectionEvents.count == 1)
    }

    @Test func choosingEasierWorkRecordsHardAvoidance() {
        var profile = CoachPreferenceProfile.empty
        let easy = CoachSession(
            id: "aerobic.easyWalk",
            kind: .easyAerobic,
            title: "Easy walk",
            durationMinutes: 30,
            modality: .walk,
            intensity: .easy,
            trainingLoadTags: ["aerobic", "easy", "lowImpact"],
            launchPayload: .cardio(type: "walk", durationMinutes: 30)
        )
        let hard = CoachSession(
            id: "aerobic.anaerobicIntervals",
            kind: .vo2Intervals,
            title: "Sprint intervals",
            durationMinutes: 20,
            modality: .run,
            intensity: .vigorous,
            trainingLoadTags: ["aerobic", "hard", "highImpact", "anaerobic"],
            launchPayload: .cardio(type: "hiit", durationMinutes: 20)
        )

        profile.recordSelection(easy, from: [hard], at: Date())

        #expect(profile.avoidedTags.contains("hard"))
        #expect(profile.avoidedTags.contains("highImpact"))
        #expect(profile.avoidedTags.contains("anaerobic"))
        #expect(profile.preferenceScore(for: hard) < 0)
        #expect(profile.avoidancePenalty(forTags: hard.trainingLoadTags) > 0)
    }
}
