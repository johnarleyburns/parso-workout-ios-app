import XCTest
import SwiftData
@testable import CadenceCore

final class DataExportTests: XCTestCase {

    private func sampleExport() -> CadenceExport {
        let setID = UUID(); let sessID = UUID()
        let set = ExportSet(id: setID, exerciseName: "Bench Press", category: "push",
                            weightKg: 100, reps: 5, order: 0, isWarmup: false,
                            rpe: 8, note: "felt strong", completedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let session = ExportSession(id: sessID, title: "Push Day",
                                    date: Date(timeIntervalSince1970: 1_700_000_000),
                                    notes: nil, sets: [set])
        return CadenceExport(exportedAt: Date(timeIntervalSince1970: 1_700_000_100), sessions: [session])
    }

    func testJSONRoundTrip() throws {
        let original = sampleExport()
        let data = try DataExport.encodeJSON(original)
        let decoded = try DataExport.decodeJSON(data)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.version, CadenceExport.currentVersion)
    }

    func testCSVHasHeaderAndRow() {
        let csv = DataExport.encodeCSV(sampleExport())
        let lines = csv.components(separatedBy: "\n")
        XCTAssertTrue(lines[0].hasPrefix("session_id,session_title"))
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[1].contains("Bench Press"))
        XCTAssertTrue(lines[1].contains("100.0"))
    }

    func testCSVEscapesCommasAndQuotes() {
        XCTAssertEqual(DataExport.csvEscape("a,b"), "\"a,b\"")
        XCTAssertEqual(DataExport.csvEscape("say \"hi\""), "\"say \"\"hi\"\"\"")
        XCTAssertEqual(DataExport.csvEscape("plain"), "plain")
    }

    func testCSVQuotesNoteWithComma() {
        let setID = UUID()
        let set = ExportSet(id: setID, exerciseName: "Row", category: nil, weightKg: 60, reps: 8,
                            order: 0, isWarmup: false, rpe: nil, note: "back, then biceps",
                            completedAt: Date(timeIntervalSince1970: 0))
        let session = ExportSession(id: UUID(), title: "Pull", date: Date(timeIntervalSince1970: 0), notes: nil, sets: [set])
        let csv = DataExport.encodeCSV(CadenceExport(sessions: [session]))
        XCTAssertTrue(csv.contains("\"back, then biceps\""))
    }

    func testJSONExportIncludesCoachPreferences() throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        var profile = CoachPreferenceProfile.empty
        let session = CoachSession(
            id: "aerobic.moderateCycle", kind: .moderateAerobic,
            title: "Steady cycle", durationMinutes: 35,
            modality: .cycle, intensity: .moderate,
            launchPayload: .cardio(type: "cycle", durationMinutes: 35)
        )
        profile.recordSelection(session, from: [], at: now)

        let export = CadenceExport(
            sessions: [], cardio: [],
            coachPreferences: profile.exportDTO
        )

        let data = try DataExport.encodeJSON(export)
        let decoded = try DataExport.decodeJSON(data)
        XCTAssertNotNil(decoded.coachPreferences)
        XCTAssertEqual(decoded.coachPreferences?.aerobicPreferences.count, 1)
        XCTAssertEqual(decoded.coachPreferences?.aerobicPreferences.first?.modality, "cycle")
        XCTAssertEqual(decoded.coachPreferences?.aerobicPreferences.first?.intent, "moderateAerobic")
    }

    func testJSONExportDecodesWhenCoachPreferencesMissing() throws {
        let json = """
        {"version":1,"exportedAt":"2025-06-01T00:00:00Z","sessions":[],"cardio":[]}
        """.data(using: .utf8)!
        let decoded = try DataExport.decodeJSON(json)
        XCTAssertNil(decoded.coachPreferences, "Older exports without coachPreferences should decode with nil")
    }

    func testCoachPreferenceExportRoundTrips() throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        var profile = CoachPreferenceProfile.empty
        profile.aerobicPreferences = [
            AerobicPreference(intent: .moderateAerobic, modality: .cycle, score: 3, updatedAt: now)
        ]
        let dto = profile.exportDTO
        let export = CadenceExport(sessions: [], cardio: [], coachPreferences: dto)
        let data = try DataExport.encodeJSON(export)
        let decoded = try DataExport.decodeJSON(data)
        XCTAssertEqual(decoded.coachPreferences?.profileVersion, 1)
        XCTAssertEqual(decoded.coachPreferences?.aerobicPreferences.first?.score, 3)
    }

    // MARK: - Lossless round-trip: export -> JSON -> fresh-store import -> re-export

    private func makeStore() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    /// "Take all my data out and put it into a fresh app, and nothing is lost":
    /// build a populated store, export → JSON → decode → merge into a brand-new
    /// store → re-export, and assert the strength history, cardio (incl. HR + route
    /// samples), assessments, and all preferences are byte-for-byte identical.
    func testLosslessRoundTripFullData() throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let ctxA = try makeStore()

        // Strength session with metadata + a working set and a warm-up set.
        let session = try WorkoutRepository.createSession(title: "Push Day", in: ctxA)
        session.date = now
        session.endedAt = now.addingTimeInterval(3000)
        session.isLogged = true
        session.planKey = "preset-5x5"
        session.warmupSeconds = 300
        session.prescribedLoadKg = 102.5
        session.plannedExerciseNames = ["Bench Press", "Overhead Press"]
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctxA)
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 100, reps: 5,
                                         rpe: 8, completedAt: now, in: ctxA)
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 40, reps: 5,
                                         isWarmup: true, completedAt: now, in: ctxA)

        // Cardio with metadata + HR + route samples.
        let cardio = CardioWorkout(type: .run, start: now, end: now.addingTimeInterval(1800),
                                   distance: 5000, activeEnergy: 320, avgHeartRate: 150,
                                   maxHeartRate: 178, source: .iphone, notes: "tempo")
        ctxA.insert(cardio)
        ctxA.insert(HRSample(t: 0, bpm: 120, cardio: cardio))
        ctxA.insert(HRSample(t: 60, bpm: 165, cardio: cardio))
        ctxA.insert(RouteSample(t: 0, lat: 37.0, lon: -122.0, elevation: 10, cardio: cardio))
        ctxA.insert(RouteSample(t: 60, lat: 37.001, lon: -122.001, elevation: 12, cardio: cardio))

        // Assessment.
        ctxA.insert(Assessment(date: now, kind: .e1RM, value: 140, inputWeight: 120, inputReps: 3,
                               exerciseName: "Bench Press"))
        try ctxA.save()

        // Preferences (settings + schedule + learned coach profile).
        var profile = CoachPreferenceProfile.empty
        profile.aerobicPreferences = [
            AerobicPreference(intent: .moderateAerobic, modality: .cycle, score: 4, updatedAt: now)
        ]
        let prefs = ExportPreferences(
            unit: "pounds", stepGoal: 12000, trainingGoal: "strength", experienceLevel: "advanced",
            favoriteRoutineIDs: ["preset-5x5"],
            schedulePreferences: CoachSchedulePreferences(strengthDaysPerWeek: 4, cardioDaysPerWeek: 2,
                                                          allowsTwoADays: true),
            coachProfile: profile)

        // Export → JSON → decode (proves Codable round-trip).
        let exportA = try WorkoutRepository.buildExport(ctxA, preferences: prefs)
        let json = try DataExport.encodeJSON(exportA)
        let decoded = try DataExport.decodeJSON(json)
        XCTAssertEqual(decoded.version, 4)

        // Merge into a brand-new store, then re-export.
        let ctxB = try makeStore()
        let added = try WorkoutRepository.merge(decoded, in: ctxB)
        XCTAssertEqual(added, 3, "1 session + 1 cardio + 1 assessment should be added")
        let exportB = try WorkoutRepository.buildExport(ctxB)

        // Strength history is identical.
        XCTAssertEqual(sorted(exportB.sessions), sorted(exportA.sessions),
                       "Strength sessions + sets + metadata must survive a fresh-install round-trip")
        // Cardio (with HR + route samples) is identical — previously dropped entirely.
        XCTAssertEqual(exportB.cardio.count, 1)
        XCTAssertEqual(exportB.cardio.first?.hrSamples?.count, 2, "HR samples must survive import")
        XCTAssertEqual(exportB.cardio.first?.routeSamples?.count, 2, "Route samples must survive import")
        XCTAssertEqual(sortedCardio(exportB.cardio), sortedCardio(exportA.cardio))
        // Assessments are identical — previously never exported/imported.
        XCTAssertEqual(exportB.assessments, exportA.assessments)

        // Preferences survive the JSON round-trip losslessly.
        XCTAssertEqual(decoded.preferences?.unit, "pounds")
        XCTAssertEqual(decoded.preferences?.stepGoal, 12000)
        XCTAssertEqual(decoded.preferences?.schedulePreferences?.strengthDaysPerWeek, 4)
        XCTAssertTrue(decoded.preferences?.schedulePreferences?.allowsTwoADays ?? false)
        XCTAssertEqual(decoded.preferences?.coachProfile?.aerobicPreferences.first?.score, 4)
    }

    /// Re-importing the same export is idempotent (dedup by id), not duplicated.
    func testMergeIsIdempotent() throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let ctxA = try makeStore()
        let s = try WorkoutRepository.createSession(title: "Day", in: ctxA)
        let ex = try WorkoutRepository.findOrCreateExercise(named: "Squat", in: ctxA)
        _ = try WorkoutRepository.addSet(to: s, exercise: ex, weightKg: 100, reps: 5, completedAt: now, in: ctxA)
        let c = CardioWorkout(type: .run, start: now, end: now.addingTimeInterval(600))
        ctxA.insert(c)
        ctxA.insert(Assessment(date: now, kind: .pushupMax, value: 30))
        try ctxA.save()

        let export = try WorkoutRepository.buildExport(ctxA)
        let ctxB = try makeStore()
        XCTAssertEqual(try WorkoutRepository.merge(export, in: ctxB), 3)
        XCTAssertEqual(try WorkoutRepository.merge(export, in: ctxB), 0, "Re-import must be a no-op (dedup by id)")
    }

    private func sorted(_ s: [ExportSession]) -> [ExportSession] {
        s.sorted { $0.id.uuidString < $1.id.uuidString }
    }
    private func sortedCardio(_ c: [ExportCardio]) -> [ExportCardio] {
        c.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    // MARK: - Legacy schedulePreferences with missing excludedCoverageParts

    func testLegacyExportWithSchedulePreferencesMissingExcludedCoverageParts() throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let dateStr = ISO8601DateFormatter.string(from: now, timeZone: .current, formatOptions: .withInternetDateTime)
        let legacyJSON = """
        {
          "version": 4,
          "exportedAt": "\(dateStr)",
          "sessions": [],
          "cardio": [],
          "assessments": [],
          "preferences": {
            "unit": "pounds",
            "trainingGoal": "hypertrophy",
            "schedulePreferences": {
              "strengthDaysPerWeek": 4,
              "cardioDaysPerWeek": 2,
              "restPreference": {"fixed": {"days": [2, 4, 6]}},
              "allowsTwoADays": true,
              "sameDayCardioTiming": "separateLater",
              "dailyStepTarget": 10000
            }
          }
        }
        """
        let decoded = try DataExport.decodeJSON(Data(legacyJSON.utf8))
        XCTAssertNotNil(decoded.preferences, "Legacy preferences should decode fully")
        XCTAssertEqual(decoded.preferences?.unit, "pounds")
        XCTAssertEqual(decoded.preferences?.schedulePreferences?.strengthDaysPerWeek, 4,
                       "Schedule preferences should survive legacy blob")
        XCTAssertEqual(decoded.preferences?.schedulePreferences?.cardioDaysPerWeek, 2)
        XCTAssertEqual(decoded.preferences?.schedulePreferences?.dailyStepTarget, 10_000)
        XCTAssertTrue(decoded.preferences?.schedulePreferences?.allowsTwoADays ?? false)
        XCTAssertEqual(decoded.preferences?.schedulePreferences?.excludedCoverageParts, [],
                       "Missing excludedCoverageParts should default to empty, not fail decode")
    }

    // MARK: - Legacy stepGoal compatibility

    func testLegacyExportWithStepGoalStillDecodes() throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let dateStr = ISO8601DateFormatter.string(from: now, timeZone: .current, formatOptions: .withInternetDateTime)
        let legacyJSON = """
        {
          "version": 4,
          "exportedAt": "\(dateStr)",
          "sessions": [],
          "cardio": [],
          "assessments": [],
          "preferences": {
            "stepGoal": 15000,
            "unit": "pounds",
            "trainingGoal": "strength"
          }
        }
        """
        let decoded = try DataExport.decodeJSON(Data(legacyJSON.utf8))
        XCTAssertEqual(decoded.preferences?.stepGoal, 15000,
                       "Legacy stepGoal field should still decode without error")
    }
}
