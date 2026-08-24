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
                                                          allowsTwoADays: true,
                                                          desiredSetsPerExercise: 4),
            coachProfile: profile)

        // Export → JSON → decode (proves Codable round-trip).
        let exportA = try WorkoutRepository.buildExport(ctxA, preferences: prefs)
        let json = try DataExport.encodeJSON(exportA)
        let decoded = try DataExport.decodeJSON(json)
        XCTAssertEqual(decoded.version, 6)

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
        XCTAssertEqual(decoded.preferences?.schedulePreferences?.desiredSetsPerExercise, 4)
        XCTAssertTrue(decoded.preferences?.schedulePreferences?.allowsTwoADays ?? false)
        XCTAssertEqual(decoded.preferences?.coachProfile?.aerobicPreferences.first?.score, 4)
    }

    // P3 (issue 11) — test-recommendation persistence round-trips.
    func testTestRecommendationStateRoundTrips() throws {
        let last = Date(timeIntervalSince1970: 1_750_000_000)
        let snoozeUntil = Date(timeIntervalSince1970: 1_750_600_000)
        let prefs = ExportPreferences(
            lastTestRecommendationAt: last,
            testRecommendationSnoozes: [AssessmentKind.e1RM.rawValue: snoozeUntil])
        let json = try DataExport.encodeJSON(CadenceExport(sessions: [], preferences: prefs))
        let decoded = try DataExport.decodeJSON(json)
        XCTAssertEqual(decoded.preferences?.lastTestRecommendationAt, last)
        XCTAssertEqual(decoded.preferences?.testRecommendationSnoozes?[AssessmentKind.e1RM.rawValue], snoozeUntil)
    }

    /// A v4/older export with no test-recommendation fields still decodes cleanly.
    func testTestRecommendationFieldsDefaultNilOnLegacyExport() throws {
        let prefs = ExportPreferences(unit: "pounds")
        let json = try DataExport.encodeJSON(CadenceExport(sessions: [], preferences: prefs))
        let decoded = try DataExport.decodeJSON(json)
        XCTAssertNil(decoded.preferences?.lastTestRecommendationAt)
        XCTAssertNil(decoded.preferences?.testRecommendationSnoozes)
        XCTAssertNil(decoded.preferences?.userAge)
    }

    // P7 (issue 7) — user age round-trips (default nil on legacy exports).
    func testUserAgeRoundTrips() throws {
        let prefs = ExportPreferences(userAge: 34)
        let json = try DataExport.encodeJSON(CadenceExport(sessions: [], preferences: prefs))
        let decoded = try DataExport.decodeJSON(json)
        XCTAssertEqual(decoded.preferences?.userAge, 34)
    }

    /// Re-importing the same export is idempotent (dedup by id), not duplicated.
    func testMergeIsIdempotent() throws {        let now = Date(timeIntervalSince1970: 1_750_000_000)
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
        XCTAssertEqual(decoded.preferences?.schedulePreferences?.desiredSetsPerExercise, 3)
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

    // MARK: - Custom exercise round-trip (v5)

    func testCustomExerciseRoundTrip() throws {
        let ctx = try makeStore()
        let ex = Exercise(name: "rotary torso", category: .core,
                           isCustom: true,
                           primaryMuscles: ["abs"], secondaryMuscles: [])
        ctx.insert(ex)
        let session = try WorkoutRepository.createSession(title: "Core Day", in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: ex, weightKg: 0, reps: 15,
                                         completedAt: Date(timeIntervalSince1970: 1_750_000_000), in: ctx)
        try ctx.save()

        let export = try WorkoutRepository.buildExport(ctx)
        XCTAssertEqual(export.version, 6)
        XCTAssertEqual(export.exercises.count, 1)
        XCTAssertEqual(export.exercises.first?.name, "rotary torso")
        XCTAssertEqual(export.exercises.first?.primaryMuscles, ["abs"],
                       "the export carries the row exactly as stored")

        let data = try DataExport.encodeJSON(export)
        let decoded = try DataExport.decodeJSON(data)
        XCTAssertEqual(decoded.exercises.count, 1)

        let newCtx = try makeStore()
        try WorkoutRepository.merge(decoded, in: newCtx)
        let imported = try WorkoutRepository.allExercises(newCtx)
        let rotary = imported.first { $0.name == "rotary torso" }
        XCTAssertNotNil(rotary)
        // Import canonicalizes onto the MuscleGroup vocabulary, so a custom
        // exercise written before the DB++ adoption keeps counting (decision D7).
        XCTAssertEqual(rotary?.primaryMuscles, ["abdominals"])
        XCTAssertTrue(rotary?.isCustom ?? false)

        let reexport = try WorkoutRepository.buildExport(newCtx)
        XCTAssertEqual(reexport.exercises.count, 1)
        XCTAssertEqual(reexport.exercises.first?.primaryMuscles, ["abdominals"])
    }

    func testV4BackwardCompat() throws {
        let v4JSON = """
        {"version":4,"exportedAt":"2026-01-01T00:00:00Z","sessions":[],"cardio":[],"assessments":[]}
        """
        let decoded = try DataExport.decodeJSON(Data(v4JSON.utf8))
        XCTAssertEqual(decoded.version, 4)
        XCTAssertTrue(decoded.exercises.isEmpty)
    }

    // MARK: - BuildExport edge cases & correctness

    func testBuildExportEmptyStore() throws {
        let ctx = try makeStore()
        let export = try WorkoutRepository.buildExport(ctx)
        XCTAssertEqual(export.sessions.count, 0)
        XCTAssertEqual(export.cardio.count, 0)
        XCTAssertEqual(export.assessments.count, 0)
        XCTAssertEqual(export.version, CadenceExport.currentVersion)
        // Encoding an empty export must not throw.
        let json = try DataExport.encodeJSON(export)
        let decoded = try DataExport.decodeJSON(json)
        XCTAssertEqual(decoded.sessions.count, 0)
    }

    func testBuildExportWithStrengthSessions() throws {
        let ctx = try makeStore()
        let now = Date(timeIntervalSince1970: 1_750_000_000)

        let session = try WorkoutRepository.createSession(title: "Leg Day", in: ctx)
        session.date = now
        session.endedAt = now.addingTimeInterval(2700)
        session.isLogged = true
        session.planKey = "preset-531"
        session.templateName = "5/3/1 Squat"
        session.warmupSeconds = 300
        session.cooldownSeconds = 300
        session.prescribedLoadKg = 142.5
        session.plannedExerciseNames = ["Back Squat", "Romanian Deadlift"]
        session.plannedRepLadder = [5, 3, 1]
        session.notes = "Week 3"

        let ex = try WorkoutRepository.findOrCreateExercise(named: "Back Squat", category: .legs, in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: ex, weightKg: 140, reps: 5, rpe: 9, completedAt: now, in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: ex, weightKg: 140, reps: 3, isWarmup: false, note: "grinder", completedAt: now, in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: ex, weightKg: 60, reps: 5, isWarmup: true, completedAt: now, in: ctx)

        try ctx.save()
        let export = try WorkoutRepository.buildExport(ctx)
        XCTAssertEqual(export.sessions.count, 1)
        XCTAssertEqual(export.cardio.count, 0)
        XCTAssertEqual(export.assessments.count, 0)

        let es = export.sessions[0]
        XCTAssertEqual(es.title, "Leg Day")
        XCTAssertEqual(es.planKey, "preset-531")
        XCTAssertEqual(es.templateName, "5/3/1 Squat")
        XCTAssertEqual(es.warmupSeconds, 300)
        XCTAssertEqual(es.cooldownSeconds, 300)
        XCTAssertEqual(es.prescribedLoadKg, 142.5)
        XCTAssertTrue(es.isLogged == true)
        XCTAssertEqual(es.plannedExerciseNames, ["Back Squat", "Romanian Deadlift"])
        XCTAssertEqual(es.plannedRepLadder, [5, 3, 1])
        XCTAssertEqual(es.notes, "Week 3")
        XCTAssertEqual(es.sets.count, 3)
        XCTAssertEqual(es.sets[0].exerciseName, "Back Squat")
        XCTAssertEqual(es.sets[0].weightKg, 140)
        XCTAssertEqual(es.sets[0].reps, 5)
        XCTAssertEqual(es.sets[0].rpe, 9)
        XCTAssertEqual(es.sets[0].isWarmup, false)
        XCTAssertNil(es.sets[0].performedBy)
        XCTAssertEqual(es.sets[1].note, "grinder")
        XCTAssertTrue(es.sets[2].isWarmup)

        // Verify the export encodes to valid JSON.
        let json = try DataExport.encodeJSON(export)
        let decoded = try DataExport.decodeJSON(json)
        XCTAssertEqual(decoded.sessions[0].planKey, "preset-531")
        XCTAssertEqual(decoded.sessions[0].plannedExerciseNames, ["Back Squat", "Romanian Deadlift"])
    }

    func testBuildExportWithCardioIncludesHRSamples() throws {
        let ctx = try makeStore()
        let now = Date(timeIntervalSince1970: 1_750_000_000)

        let cardio = CardioWorkout(type: .run, start: now, end: now.addingTimeInterval(1800),
                                   distance: 5000, activeEnergy: 320, avgHeartRate: 150,
                                   maxHeartRate: 178, source: .iphone, notes: "Tempo run")
        cardio.laps = 4
        cardio.targetLaps = 4
        cardio.isLogged = true
        cardio.customTitle = "Park 5k"
        ctx.insert(cardio)
        ctx.insert(HRSample(t: 0, bpm: 120, cardio: cardio))
        ctx.insert(HRSample(t: 600, bpm: 165, cardio: cardio))
        ctx.insert(RouteSample(t: 0, lat: 37.0, lon: -122.0, elevation: 10, cardio: cardio))
        try ctx.save()

        let export = try WorkoutRepository.buildExport(ctx)
        XCTAssertEqual(export.cardio.count, 1)
        let ec = export.cardio[0]
        XCTAssertEqual(ec.type, CardioType.run.rawValue)
        XCTAssertEqual(ec.distanceMeters, 5000)
        XCTAssertEqual(ec.avgHeartRate, 150)
        XCTAssertEqual(ec.maxHeartRate, 178)
        XCTAssertEqual(ec.laps, 4)
        XCTAssertEqual(ec.targetLaps, 4)
        XCTAssertEqual(ec.customTitle, "Park 5k")
        XCTAssertTrue(ec.isLogged == true)
        XCTAssertEqual(ec.hrSamples?.count, 2)
        XCTAssertEqual(ec.hrSamples?.first?.bpm, 120)
        XCTAssertEqual(ec.hrSamples?.last?.bpm, 165)
        XCTAssertEqual(ec.routeSamples?.count, 1)
        XCTAssertEqual(ec.routeSamples?.first?.lat, 37.0)

        // Round-trip verification.
        let json = try DataExport.encodeJSON(export)
        let decoded = try DataExport.decodeJSON(json)
        XCTAssertEqual(decoded.cardio[0].hrSamples?.count, 2)
        XCTAssertEqual(decoded.cardio[0].routeSamples?.count, 1)
    }

    func testBuildExportWithAssessments() throws {
        let ctx = try makeStore()
        let now = Date(timeIntervalSince1970: 1_750_000_000)

        let e1rmID = UUID()
        let pushupID = UUID()
        ctx.insert(Assessment(id: e1rmID, date: now, kind: .e1RM, value: 140, inputWeight: 120, inputReps: 3,
                              exerciseName: "Bench Press"))
        ctx.insert(Assessment(id: pushupID, date: now.addingTimeInterval(86400), kind: .pushupMax, value: 42))
        try ctx.save()

        let export = try WorkoutRepository.buildExport(ctx)
        XCTAssertEqual(export.assessments.count, 2)

        let byID = Dictionary(uniqueKeysWithValues: export.assessments.map { ($0.id, $0) })
        XCTAssertEqual(byID[e1rmID]?.kind, AssessmentKind.e1RM.rawValue)
        XCTAssertEqual(byID[e1rmID]?.exerciseName, "Bench Press")
        XCTAssertEqual(byID[e1rmID]?.inputWeight, 120)
        XCTAssertEqual(byID[e1rmID]?.inputReps, 3)
        XCTAssertEqual(byID[pushupID]?.kind, AssessmentKind.pushupMax.rawValue)
        XCTAssertEqual(byID[pushupID]?.value, 42)

        let json = try DataExport.encodeJSON(export)
        let decoded = try DataExport.decodeJSON(json)
        XCTAssertEqual(decoded.assessments.count, 2)
    }

    func testBuildExportWithPreferencesRoundTrip() throws {
        let ctx = try makeStore()
        let now = Date(timeIntervalSince1970: 1_750_000_000)

        var profile = CoachPreferenceProfile.empty
        profile.aerobicPreferences = [
            AerobicPreference(intent: .moderateAerobic, modality: .cycle, score: 5, updatedAt: now)
        ]
        profile.strengthPreferences = [
            StrengthPreference(pattern: .horizontalPush, exerciseName: "Bench Press", score: 3, updatedAt: now)
        ]
        profile.avoidedTags = ["boring"]

        let prefs = ExportPreferences(
            unit: "pounds", prRule: "heaviestSet",
            oneRepMaxFormula: "brzycki", stepGoal: 12_000,
            weeklyCardioMinutesGoal: 200, restSeconds: 120,
            warmupMinutes: 5, cooldownMinutes: 5,
            autoStartRest: true, idleTimeoutMinutes: 3,
            plateRounding: true, autoSaveHealth: false,
            workoutSounds: true, preWorkoutCountdown: 5,
            trainingGoal: "strength", experienceLevel: "intermediate",
            favoriteRoutineIDs: ["preset-531", "preset-5x5"],
            hasCompletedOnboarding: true,
            schedulePreferences: CoachSchedulePreferences(strengthDaysPerWeek: 4,
                                                          cardioDaysPerWeek: 2,
                                                          allowsTwoADays: false),
            coachProfile: profile)

        let export = try WorkoutRepository.buildExport(ctx, preferences: prefs)
        XCTAssertNotNil(export.preferences)
        XCTAssertEqual(export.preferences?.unit, "pounds")
        XCTAssertEqual(export.preferences?.prRule, "heaviestSet")
        XCTAssertEqual(export.preferences?.stepGoal, 12_000)
        XCTAssertEqual(export.preferences?.schedulePreferences?.strengthDaysPerWeek, 4)
        XCTAssertEqual(export.preferences?.coachProfile?.aerobicPreferences.first?.score, 5)
        XCTAssertEqual(export.preferences?.favoriteRoutineIDs, ["preset-531", "preset-5x5"])
        XCTAssertTrue(export.preferences?.hasCompletedOnboarding == true)

        let json = try DataExport.encodeJSON(export)
        let decoded = try DataExport.decodeJSON(json)
        XCTAssertEqual(decoded.preferences?.unit, "pounds")
        XCTAssertEqual(decoded.preferences?.oneRepMaxFormula, "brzycki")
        XCTAssertEqual(decoded.preferences?.schedulePreferences?.cardioDaysPerWeek, 2)
        XCTAssertEqual(decoded.preferences?.coachProfile?.strengthPreferences.first?.exerciseName, "Bench Press")
        XCTAssertEqual(decoded.preferences?.coachProfile?.avoidedTags, ["boring"])
    }

    func testFullRoundTripReExportMatches() throws {
        let ctxA = try makeStore()
        let now = Date(timeIntervalSince1970: 1_750_000_000)

        // Strength with metadata.
        let session = try WorkoutRepository.createSession(title: "Full Body", in: ctxA)
        session.date = now
        session.endedAt = now.addingTimeInterval(3600)
        session.isLogged = true
        session.planKey = "preset-ppl"
        session.warmupSeconds = 300
        session.plannedExerciseNames = ["Squat", "Bench", "Row"]
        let squat = try WorkoutRepository.findOrCreateExercise(named: "Back Squat", category: .legs, in: ctxA)
        _ = try WorkoutRepository.addSet(to: session, exercise: squat, weightKg: 100, reps: 5, rpe: 8, completedAt: now, in: ctxA)
        _ = try WorkoutRepository.addSet(to: session, exercise: squat, weightKg: 102.5, reps: 5, rpe: 8, completedAt: now, in: ctxA)

        // Cardio with HR samples.
        let cardio = CardioWorkout(type: .run, start: now, end: now.addingTimeInterval(1200),
                                   distance: 3000, activeEnergy: 210, avgHeartRate: 145,
                                   source: .iphone)
        ctxA.insert(cardio)
        ctxA.insert(HRSample(t: 0, bpm: 130, cardio: cardio))
        // Assessment.
        ctxA.insert(Assessment(date: now, kind: .pushupMax, value: 35, notes: "AM"))
        try ctxA.save()

        // Preferences.
        let prefs = ExportPreferences(
            unit: "kilograms", trainingGoal: "hypertrophy",
            schedulePreferences: CoachSchedulePreferences(strengthDaysPerWeek: 5, cardioDaysPerWeek: 3))

        let exportA = try WorkoutRepository.buildExport(ctxA, preferences: prefs)
        let json = try DataExport.encodeJSON(exportA)
        let decoded = try DataExport.decodeJSON(json)

        // Merge into fresh store.
        let ctxB = try makeStore()
        let added = try WorkoutRepository.merge(decoded, in: ctxB)
        XCTAssertEqual(added, 3, "1 session + 1 cardio + 1 assessment")

        var profile = CoachPreferenceProfile.empty
        profile.aerobicPreferences = [
            AerobicPreference(intent: .moderateAerobic, modality: .run, score: 2, updatedAt: now)
        ]
        let prefsB = ExportPreferences(unit: "pounds", coachProfile: profile)
        let exportB = try WorkoutRepository.buildExport(ctxB,
                                                        coachPreferences: profile.exportDTO,
                                                        preferences: prefsB)

        // Core data must match (ignore exportedAt which differs).
        XCTAssertEqual(exportB.sessions.count, exportA.sessions.count)
        XCTAssertEqual(exportB.cardio.count, exportA.cardio.count)
        XCTAssertEqual(exportB.assessments.count, exportA.assessments.count)

        // Compare sessions by id.
        let sessionMapA = Dictionary(uniqueKeysWithValues: exportA.sessions.map { ($0.id, $0) })
        let sessionMapB = Dictionary(uniqueKeysWithValues: exportB.sessions.map { ($0.id, $0) })
        for (id, a) in sessionMapA {
            guard let b = sessionMapB[id] else { XCTFail("Session \(id) missing in re-export"); continue }
            XCTAssertEqual(b.title, a.title)
            XCTAssertEqual(b.planKey, a.planKey)
            XCTAssertEqual(b.sets.count, a.sets.count)
            XCTAssertEqual(b.warmupSeconds, a.warmupSeconds)
        }

        // Cardio must match.
        let cardioMapA = Dictionary(uniqueKeysWithValues: exportA.cardio.map { ($0.id, $0) })
        let cardioMapB = Dictionary(uniqueKeysWithValues: exportB.cardio.map { ($0.id, $0) })
        for (id, a) in cardioMapA {
            guard let b = cardioMapB[id] else { XCTFail("Cardio \(id) missing in re-export"); continue }
            XCTAssertEqual(b.hrSamples?.count, a.hrSamples?.count)
            XCTAssertEqual(b.distanceMeters, a.distanceMeters)
        }

        // Assessments must match.
        XCTAssertEqual(exportB.assessments, exportA.assessments)
    }

    func testEmptyExportEncodesToValidJSON() throws {
        let empty = CadenceExport(sessions: [])
        let json = try DataExport.encodeJSON(empty)
        let str = String(data: json, encoding: .utf8)!
        XCTAssertTrue(str.contains("\"sessions\""))
        XCTAssertTrue(str.contains("\"cardio\""))
        XCTAssertTrue(str.contains("\"version\""))
        // Must be parseable back.
        let decoded = try DataExport.decodeJSON(json)
        XCTAssertEqual(decoded.sessions.count, 0)
        XCTAssertEqual(decoded.version, CadenceExport.currentVersion)
    }

    func testMergeDoesNotLoseSessionMetadata() throws {
        let ctxA = try makeStore()
        let now = Date(timeIntervalSince1970: 1_750_000_000)

        let session = try WorkoutRepository.createSession(title: "Upper", in: ctxA)
        session.date = now
        session.endedAt = now.addingTimeInterval(2400)
        session.isLogged = true
        session.planKey = "preset-531"
        session.templateName = "5/3/1 OHP"
        session.warmupSeconds = 300
        session.cooldownSeconds = 300
        session.prescribedLoadKg = 67.5
        session.plannedExerciseNames = ["Overhead Press"]
        session.plannedRepLadder = [5, 3, 1]
        session.notes = "Deload"

        let ohp = try WorkoutRepository.findOrCreateExercise(named: "Overhead Press", category: .push, in: ctxA)
        _ = try WorkoutRepository.addSet(to: session, exercise: ohp, weightKg: 65, reps: 5, rpe: 7, completedAt: now, in: ctxA)
        session.activePartnerIDs = ["partner-uuid-1"]
        try ctxA.save()

        let export = try WorkoutRepository.buildExport(ctxA)
        let ctxB = try makeStore()
        try WorkoutRepository.merge(export, in: ctxB)

        let sessions = try WorkoutRepository.allSessions(ctxB)
        XCTAssertEqual(sessions.count, 1)
        let s = sessions[0]
        XCTAssertEqual(s.title, "Upper")
        XCTAssertEqual(s.planKey, "preset-531")
        XCTAssertEqual(s.templateName, "5/3/1 OHP")
        XCTAssertEqual(s.warmupSeconds, 300)
        XCTAssertEqual(s.cooldownSeconds, 300)
        XCTAssertEqual(s.prescribedLoadKg, 67.5)
        XCTAssertEqual(s.plannedExerciseNames, ["Overhead Press"])
        XCTAssertEqual(s.plannedRepLadder, [5, 3, 1])
        XCTAssertEqual(s.notes, "Deload")
        XCTAssertTrue(s.isLogged)
        XCTAssertEqual(s.activePartnerIDs, ["partner-uuid-1"])
        XCTAssertEqual(s.orderedSets.count, 1)
        XCTAssertEqual(s.orderedSets[0].weight, 65)
    }

    // MARK: - Task.detached export (off-main-thread) → import → re-export

    /// Validates the exact pattern ExportView now uses: spawn a detached task with
    /// the ModelContainer, create a fresh ModelContext inside it, build the export
    /// AND encode it — all off the main thread — then merge into a fresh store and
    /// assert the lossless round-trip. This catches any Sendable/isolation issue
    /// that the prior @ModelActor approach may have masked.
    func testDetachedExportThenImportThenReExportIsLossless() async throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let container = try CadenceStore.makeModelContainer(inMemory: true)

        // Populate store A via its own context.
        let ctxA = ModelContext(container)
        // Strength: 2 sessions with multiple sets each — simulates a user with history.
        let s1 = try WorkoutRepository.createSession(title: "Leg Day", in: ctxA)
        s1.date = now; s1.endedAt = now.addingTimeInterval(3000); s1.isLogged = true
        s1.planKey = "preset-531"; s1.warmupSeconds = 300; s1.prescribedLoadKg = 142.5
        let squat = try WorkoutRepository.findOrCreateExercise(named: "Back Squat", category: .legs, in: ctxA)
        _ = try WorkoutRepository.addSet(to: s1, exercise: squat, weightKg: 140, reps: 5, rpe: 9, completedAt: now, in: ctxA)
        _ = try WorkoutRepository.addSet(to: s1, exercise: squat, weightKg: 142.5, reps: 3, rpe: 9.5, completedAt: now, in: ctxA)

        let s2 = try WorkoutRepository.createSession(title: "Push Day", in: ctxA)
        s2.date = now.addingTimeInterval(86400); s2.isLogged = true
        s2.planKey = "preset-ppl"; s2.plannedExerciseNames = ["Bench Press", "OHP"]
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", category: .push, in: ctxA)
        _ = try WorkoutRepository.addSet(to: s2, exercise: bench, weightKg: 100, reps: 5, rpe: 8, completedAt: now, in: ctxA)
        _ = try WorkoutRepository.addSet(to: s2, exercise: bench, weightKg: 105, reps: 3, rpe: 9, completedAt: now, in: ctxA)

        // Cardio with HR + route samples.
        let cardio = CardioWorkout(type: .run, start: now, end: now.addingTimeInterval(1800),
                                   distance: 5000, activeEnergy: 320, avgHeartRate: 150,
                                   maxHeartRate: 178, source: .iphone, notes: "tempo")
        cardio.laps = 4; cardio.isLogged = true
        ctxA.insert(cardio)
        ctxA.insert(HRSample(t: 0, bpm: 120, cardio: cardio))
        ctxA.insert(HRSample(t: 600, bpm: 165, cardio: cardio))
        ctxA.insert(RouteSample(t: 0, lat: 37.0, lon: -122.0, elevation: 10, cardio: cardio))

        // Assessment.
        ctxA.insert(Assessment(date: now, kind: .pushupMax, value: 42, notes: "morning"))

        // Preferences.
        var profile = CoachPreferenceProfile.empty
        profile.aerobicPreferences = [
            AerobicPreference(intent: .moderateAerobic, modality: .cycle, score: 5, updatedAt: now)
        ]
        let prefs = ExportPreferences(
            unit: "kilograms", prRule: "heaviestSet", stepGoal: 10_000,
            trainingGoal: "strength", experienceLevel: "intermediate",
            schedulePreferences: CoachSchedulePreferences(strengthDaysPerWeek: 4, cardioDaysPerWeek: 2),
            coachProfile: profile)

        try ctxA.save()

        // --- Phase 1: build export + encode in a detached task (matching ExportView.rebuild()) ---
        let coachDTO = profile.exportDTO
        let encodedJSON = try await Task.detached(priority: .userInitiated) {
            let ctx = ModelContext(container)
            let export = try WorkoutRepository.buildExport(ctx,
                coachPreferences: coachDTO,
                preferences: prefs)
            return try DataExport.encodeJSON(export)
        }.value

        // Phase 2: decode & verify.
        let decoded = try DataExport.decodeJSON(encodedJSON)
        XCTAssertEqual(decoded.version, 6)
        XCTAssertEqual(decoded.sessions.count, 2)
        XCTAssertEqual(decoded.cardio.count, 1)
        XCTAssertEqual(decoded.assessments.count, 1)
        XCTAssertEqual(decoded.preferences?.unit, "kilograms")
        XCTAssertEqual(decoded.preferences?.prRule, "heaviestSet")
        XCTAssertEqual(decoded.preferences?.coachProfile?.aerobicPreferences.first?.score, 5)

        // Phase 3: merge into a fresh store, then export again from it — drill into
        // every facet to prove nothing was lost.
        let containerB = try CadenceStore.makeModelContainer(inMemory: true)
        let ctxB = ModelContext(containerB)
        let added = try WorkoutRepository.merge(decoded, in: ctxB)
        XCTAssertEqual(added, 4, "2 sessions + 1 cardio + 1 assessment")

        let reExported = try WorkoutRepository.buildExport(ctxB,
            preferences: ExportPreferences(unit: "kilograms"))
        XCTAssertEqual(reExported.sessions.count, 2)
        XCTAssertEqual(reExported.cardio.count, 1)
        XCTAssertEqual(reExported.assessments.count, 1)

        // Verify strength sessions by title.
        let titles = Set(reExported.sessions.map(\.title))
        XCTAssertTrue(titles.contains("Leg Day"))
        XCTAssertTrue(titles.contains("Push Day"))

        // Verify set-level data survived.
        let allSets = reExported.sessions.flatMap(\.sets)
        XCTAssertEqual(allSets.count, 4)
        XCTAssertTrue(allSets.contains(where: { $0.exerciseName == "Back Squat" && $0.weightKg == 140 }))
        XCTAssertTrue(allSets.contains(where: { $0.exerciseName == "Bench Press" && $0.weightKg == 105 }))

        // Verify cardio HR/route samples survived the full tour.
        let reCardio = reExported.cardio.first
        XCTAssertNotNil(reCardio)
        XCTAssertEqual(reCardio?.hrSamples?.count, 2)
        XCTAssertEqual(reCardio?.routeSamples?.count, 1)
        XCTAssertEqual(reCardio?.notes, "tempo")

        // Verify assessment.
        XCTAssertEqual(reExported.assessments.first?.value, 42)
    }

    // MARK: - Per-performer prescriptions (field test 2026-08-18 #4)

    func testExportRoundTripsPerformerPrescriptions() throws {
        let partnerID = UUID().uuidString
        let performerPlans = [
            PlannedPerformerPrescription(performerID: nil, exercises: [
                PlannedExercisePrescription(exerciseName: "Bench Press",
                                            sets: [PlannedSetPrescription(targetReps: 8, targetWeightKg: 100)])]),
            PlannedPerformerPrescription(performerID: partnerID, exercises: [
                PlannedExercisePrescription(exerciseName: "Bench Press",
                                            sets: [PlannedSetPrescription(targetReps: 12, targetWeightKg: 60)])])
        ]
        let session = ExportSession(id: UUID(), title: "Push Day",
                                    date: Date(timeIntervalSince1970: 1_700_000_000),
                                    notes: nil, sets: [],
                                    plannedPerformerPrescriptions: performerPlans)
        let original = CadenceExport(sessions: [session])

        let decoded = try DataExport.decodeJSON(DataExport.encodeJSON(original))

        XCTAssertEqual(decoded.sessions.first?.plannedPerformerPrescriptions, performerPlans)
    }

    func testImportOfALegacyExportWithoutPerformerPrescriptionsSucceeds() throws {
        // A pre-Phase-9 export simply has no such key: the encoder omits a nil
        // optional entirely, which is exactly the legacy on-disk shape.
        let legacy = CadenceExport(sessions: [ExportSession(
            id: UUID(), title: "Push Day", date: Date(timeIntervalSince1970: 1_700_000_000),
            notes: nil, sets: [],
            plannedPrescriptions: [PlannedExercisePrescription(
                exerciseName: "Bench Press",
                sets: [PlannedSetPrescription(targetReps: 5, targetWeightKg: 100)])])])
        let data = try DataExport.encodeJSON(legacy)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("plannedPerformerPrescriptions"),
                       "The legacy fixture must not carry the new key at all")

        let decoded = try DataExport.decodeJSON(data)

        XCTAssertEqual(decoded.sessions.count, 1)
        XCTAssertNil(decoded.sessions.first?.plannedPerformerPrescriptions,
                     "An export written before this field must decode with it absent")
        XCTAssertEqual(decoded.sessions.first?.plannedPrescriptions?.first?.sets.first?.targetReps, 5,
                       "and the owner's plan must survive untouched")
    }
}
