#if canImport(SwiftData)
import Foundation
import Testing
import SwiftData
@testable import CadenceCore

struct DataExportTests {

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

    @Test func jSONRoundTrip() throws {
        let original = sampleExport()
        let data = try DataExport.encodeJSON(original)
        let decoded = try DataExport.decodeJSON(data)
        #expect(decoded == original)
        #expect(decoded.version == CadenceExport.currentVersion)
    }

    @Test func cSVHasHeaderAndRow() {
        let csv = DataExport.encodeCSV(sampleExport())
        let lines = csv.components(separatedBy: "\n")
        #expect(lines[0].hasPrefix("session_id,session_title"))
        #expect(lines.count == 2)
        #expect(lines[1].contains("Bench Press"))
        #expect(lines[1].contains("100.0"))
    }

    @Test func cSVEscapesCommasAndQuotes() {
        #expect(DataExport.csvEscape("a,b") == "\"a,b\"")
        #expect(DataExport.csvEscape("say \"hi\"") == "\"say \"\"hi\"\"\"")
        #expect(DataExport.csvEscape("plain") == "plain")
    }

    @Test func cSVQuotesNoteWithComma() {
        let setID = UUID()
        let set = ExportSet(id: setID, exerciseName: "Row", category: nil, weightKg: 60, reps: 8,
                            order: 0, isWarmup: false, rpe: nil, note: "back, then biceps",
                            completedAt: Date(timeIntervalSince1970: 0))
        let session = ExportSession(id: UUID(), title: "Pull", date: Date(timeIntervalSince1970: 0), notes: nil, sets: [set])
        let csv = DataExport.encodeCSV(CadenceExport(sessions: [session]))
        #expect(csv.contains("\"back, then biceps\""))
    }

    @Test func jSONExportIncludesCoachPreferences() throws {
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
        #expect(decoded.coachPreferences != nil)
        #expect(decoded.coachPreferences?.aerobicPreferences.count == 1)
        #expect(decoded.coachPreferences?.aerobicPreferences.first?.modality == "cycle")
        #expect(decoded.coachPreferences?.aerobicPreferences.first?.intent == "moderateAerobic")
    }

    @Test func jSONExportDecodesWhenCoachPreferencesMissing() throws {
        let json = """
        {"version":1,"exportedAt":"2025-06-01T00:00:00Z","sessions":[],"cardio":[]}
        """.data(using: .utf8)!
        let decoded = try DataExport.decodeJSON(json)
        #expect(decoded.coachPreferences == nil, "Older exports without coachPreferences should decode with nil")
    }

    @Test func coachPreferenceExportRoundTrips() throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        var profile = CoachPreferenceProfile.empty
        profile.aerobicPreferences = [
            AerobicPreference(intent: .moderateAerobic, modality: .cycle, score: 3, updatedAt: now)
        ]
        let dto = profile.exportDTO
        let export = CadenceExport(sessions: [], cardio: [], coachPreferences: dto)
        let data = try DataExport.encodeJSON(export)
        let decoded = try DataExport.decodeJSON(data)
        #expect(decoded.coachPreferences?.profileVersion == 1)
        #expect(decoded.coachPreferences?.aerobicPreferences.first?.score == 3)
    }

    // MARK: - Lossless round-trip: export -> JSON -> fresh-store import -> re-export

    private func makeStore() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    /// "Take all my data out and put it into a fresh app, and nothing is lost":
    /// build a populated store, export → JSON → decode → merge into a brand-new
    /// store → re-export, and assert the strength history, cardio (incl. HR + route
    /// samples), assessments, and all preferences are byte-for-byte identical.
    @Test func losslessRoundTripFullData() throws {
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
            unit: "pounds", trainingGoal: "strength", experienceLevel: "advanced",
            favoriteRoutineIDs: ["preset-5x5"],
            schedulePreferences: CoachSchedulePreferences(allowsTwoADays: true,
                                                          desiredSetsPerExercise: 4),
            coachProfile: profile)

        // Export → JSON → decode (proves Codable round-trip).
        let exportA = try WorkoutRepository.buildExport(ctxA, preferences: prefs)
        let json = try DataExport.encodeJSON(exportA)
        let decoded = try DataExport.decodeJSON(json)
        #expect(decoded.version == CadenceExport.currentVersion)

        // Merge into a brand-new store, then re-export.
        let ctxB = try makeStore()
        let added = try WorkoutRepository.merge(decoded, in: ctxB)
        #expect(added == 3, "1 session + 1 cardio + 1 assessment should be added")
        let exportB = try WorkoutRepository.buildExport(ctxB)

        // Strength history is identical.
        #expect(sorted(exportB.sessions) == sorted(exportA.sessions),
                       "Strength sessions + sets + metadata must survive a fresh-install round-trip")
        // Cardio (with HR + route samples) is identical — previously dropped entirely.
        #expect(exportB.cardio.count == 1)
        #expect(exportB.cardio.first?.hrSamples?.count == 2, "HR samples must survive import")
        #expect(exportB.cardio.first?.routeSamples?.count == 2, "Route samples must survive import")
        #expect(sortedCardio(exportB.cardio) == sortedCardio(exportA.cardio))
        // Assessments are identical — previously never exported/imported.
        #expect(exportB.assessments == exportA.assessments)

        // Preferences survive the JSON round-trip losslessly.
        #expect(decoded.preferences?.unit == "pounds")
        #expect(decoded.preferences?.schedulePreferences?.desiredSetsPerExercise == 4)
        #expect(decoded.preferences?.schedulePreferences?.allowsTwoADays ?? false)
        #expect(decoded.preferences?.coachProfile?.aerobicPreferences.first?.score == 4)
    }

    // P3 (issue 11) — test-recommendation persistence round-trips.
    @Test func testRecommendationStateRoundTrips() throws {
        let last = Date(timeIntervalSince1970: 1_750_000_000)
        let snoozeUntil = Date(timeIntervalSince1970: 1_750_600_000)
        let prefs = ExportPreferences(
            lastTestRecommendationAt: last,
            testRecommendationSnoozes: [AssessmentKind.e1RM.rawValue: snoozeUntil])
        let json = try DataExport.encodeJSON(CadenceExport(sessions: [], preferences: prefs))
        let decoded = try DataExport.decodeJSON(json)
        #expect(decoded.preferences?.lastTestRecommendationAt == last)
        #expect(decoded.preferences?.testRecommendationSnoozes?[AssessmentKind.e1RM.rawValue] == snoozeUntil)
    }

    /// A v4/older export with no test-recommendation fields still decodes cleanly.
    @Test func testRecommendationFieldsDefaultNilOnLegacyExport() throws {
        let prefs = ExportPreferences(unit: "pounds")
        let json = try DataExport.encodeJSON(CadenceExport(sessions: [], preferences: prefs))
        let decoded = try DataExport.decodeJSON(json)
        #expect(decoded.preferences?.lastTestRecommendationAt == nil)
        #expect(decoded.preferences?.testRecommendationSnoozes == nil)
        #expect(decoded.preferences?.userAge == nil)
    }

    // P7 (issue 7) — user age round-trips (default nil on legacy exports).
    @Test func userAgeRoundTrips() throws {
        let prefs = ExportPreferences(userAge: 34)
        let json = try DataExport.encodeJSON(CadenceExport(sessions: [], preferences: prefs))
        let decoded = try DataExport.decodeJSON(json)
        #expect(decoded.preferences?.userAge == 34)
    }

    /// Re-importing the same export is idempotent (dedup by id), not duplicated.
    @Test func mergeIsIdempotent() throws {        let now = Date(timeIntervalSince1970: 1_750_000_000)
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
        #expect(try WorkoutRepository.merge(export, in: ctxB) == 3)
        #expect(try WorkoutRepository.merge(export, in: ctxB) == 0, "Re-import must be a no-op (dedup by id)")
    }

    private func sorted(_ s: [ExportSession]) -> [ExportSession] {
        s.sorted { $0.id.uuidString < $1.id.uuidString }
    }
    private func sortedCardio(_ c: [ExportCardio]) -> [ExportCardio] {
        c.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    // MARK: - Legacy schedulePreferences with missing excludedCoverageParts

    @Test func legacyExportWithSchedulePreferencesMissingExcludedCoverageParts() throws {
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
        #expect(decoded.preferences != nil, "Legacy preferences should decode fully")
        #expect(decoded.preferences?.unit == "pounds")
        #expect(decoded.preferences?.schedulePreferences?.sameDayCardioTiming == .separateLater,
                       "Schedule preferences should survive legacy blob")
        #expect(decoded.preferences?.schedulePreferences?.dailyStepTarget == 10_000)
        #expect(decoded.preferences?.schedulePreferences?.desiredSetsPerExercise == 3)
        #expect(decoded.preferences?.schedulePreferences?.allowsTwoADays ?? false)
        #expect(decoded.preferences?.schedulePreferences?.trackedMuscleGroups ==
                       MuscleGroup.defaultTracked,
                       "A payload with no tracked-group key should fall back to the defaults, not fail decode")
    }

    // MARK: - Retired goal keys (stepGoal, weeklyCardioMinutesGoal, day targets)

    @Test func legacyExportWithStepGoalStillDecodes() throws {
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
            "weeklyCardioMinutesGoal": 200,
            "unit": "pounds",
            "trainingGoal": "strength",
            "schedulePreferences": {"strengthDaysPerWeek": 4, "cardioDaysPerWeek": 2}
          }
        }
        """
        let decoded = try DataExport.decodeJSON(Data(legacyJSON.utf8))
        #expect(decoded.preferences?.unit == "pounds",
                       "Legacy goal keys must be ignored without failing decode")
        let reencoded = try #require(String(data: DataExport.encodeJSON(decoded), encoding: .utf8))
        for key in ["stepGoal", "weeklyCardioMinutesGoal", "strengthDaysPerWeek", "cardioDaysPerWeek"] {
            #expect(!reencoded.contains(key), "\(key) must not be re-emitted")
        }
    }

    // MARK: - Custom exercise round-trip (v5)

    @Test func customExerciseRoundTrip() throws {
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
        #expect(export.version == CadenceExport.currentVersion)
        #expect(export.exercises.count == 1)
        #expect(export.exercises.first?.name == "rotary torso")
        #expect(export.exercises.first?.primaryMuscles == ["abs"],
                       "the export carries the row exactly as stored")

        let data = try DataExport.encodeJSON(export)
        let decoded = try DataExport.decodeJSON(data)
        #expect(decoded.exercises.count == 1)

        let newCtx = try makeStore()
        try WorkoutRepository.merge(decoded, in: newCtx)
        let imported = try WorkoutRepository.allExercises(newCtx)
        let rotary = imported.first { $0.name == "rotary torso" }
        #expect(rotary != nil)
        // Import canonicalizes onto the MuscleGroup vocabulary, so a custom
        // exercise written before the DB++ adoption keeps counting (decision D7).
        #expect(rotary?.primaryMuscles == ["abdominals"])
        #expect(rotary?.isCustom ?? false)

        let reexport = try WorkoutRepository.buildExport(newCtx)
        #expect(reexport.exercises.count == 1)
        #expect(reexport.exercises.first?.primaryMuscles == ["abdominals"])
    }

    @Test func v4BackwardCompat() throws {
        let v4JSON = """
        {"version":4,"exportedAt":"2026-01-01T00:00:00Z","sessions":[],"cardio":[],"assessments":[]}
        """
        let decoded = try DataExport.decodeJSON(Data(v4JSON.utf8))
        #expect(decoded.version == 4)
        #expect(decoded.exercises.isEmpty)
    }

    // MARK: - BuildExport edge cases & correctness

    @Test func buildExportEmptyStore() throws {
        let ctx = try makeStore()
        let export = try WorkoutRepository.buildExport(ctx)
        #expect(export.sessions.count == 0)
        #expect(export.cardio.count == 0)
        #expect(export.assessments.count == 0)
        #expect(export.version == CadenceExport.currentVersion)
        // Encoding an empty export must not throw.
        let json = try DataExport.encodeJSON(export)
        let decoded = try DataExport.decodeJSON(json)
        #expect(decoded.sessions.count == 0)
    }

    @Test func buildExportWithStrengthSessions() throws {
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
        #expect(export.sessions.count == 1)
        #expect(export.cardio.count == 0)
        #expect(export.assessments.count == 0)

        let es = export.sessions[0]
        #expect(es.title == "Leg Day")
        #expect(es.planKey == "preset-531")
        #expect(es.templateName == "5/3/1 Squat")
        #expect(es.warmupSeconds == 300)
        #expect(es.cooldownSeconds == 300)
        #expect(es.prescribedLoadKg == 142.5)
        #expect(es.isLogged == true)
        #expect(es.plannedExerciseNames == ["Back Squat", "Romanian Deadlift"])
        #expect(es.plannedRepLadder == [5, 3, 1])
        #expect(es.notes == "Week 3")
        #expect(es.sets.count == 3)
        #expect(es.sets[0].exerciseName == "Back Squat")
        #expect(es.sets[0].weightKg == 140)
        #expect(es.sets[0].reps == 5)
        #expect(es.sets[0].rpe == 9)
        #expect(es.sets[0].isWarmup == false)
        #expect(es.sets[0].performedBy == nil)
        #expect(es.sets[1].note == "grinder")
        #expect(es.sets[2].isWarmup)

        // Verify the export encodes to valid JSON.
        let json = try DataExport.encodeJSON(export)
        let decoded = try DataExport.decodeJSON(json)
        #expect(decoded.sessions[0].planKey == "preset-531")
        #expect(decoded.sessions[0].plannedExerciseNames == ["Back Squat", "Romanian Deadlift"])
    }

    @Test func buildExportWithCardioIncludesHRSamples() throws {
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
        #expect(export.cardio.count == 1)
        let ec = export.cardio[0]
        #expect(ec.type == CardioType.run.rawValue)
        #expect(ec.distanceMeters == 5000)
        #expect(ec.avgHeartRate == 150)
        #expect(ec.maxHeartRate == 178)
        #expect(ec.laps == 4)
        #expect(ec.targetLaps == 4)
        #expect(ec.customTitle == "Park 5k")
        #expect(ec.isLogged == true)
        #expect(ec.hrSamples?.count == 2)
        #expect(ec.hrSamples?.first?.bpm == 120)
        #expect(ec.hrSamples?.last?.bpm == 165)
        #expect(ec.routeSamples?.count == 1)
        #expect(ec.routeSamples?.first?.lat == 37.0)

        // Round-trip verification.
        let json = try DataExport.encodeJSON(export)
        let decoded = try DataExport.decodeJSON(json)
        #expect(decoded.cardio[0].hrSamples?.count == 2)
        #expect(decoded.cardio[0].routeSamples?.count == 1)
    }

    @Test func buildExportWithAssessments() throws {
        let ctx = try makeStore()
        let now = Date(timeIntervalSince1970: 1_750_000_000)

        let e1rmID = UUID()
        let pushupID = UUID()
        ctx.insert(Assessment(id: e1rmID, date: now, kind: .e1RM, value: 140, inputWeight: 120, inputReps: 3,
                              exerciseName: "Bench Press"))
        ctx.insert(Assessment(id: pushupID, date: now.addingTimeInterval(86400), kind: .pushupMax, value: 42))
        try ctx.save()

        let export = try WorkoutRepository.buildExport(ctx)
        #expect(export.assessments.count == 2)

        let byID = Dictionary(uniqueKeysWithValues: export.assessments.map { ($0.id, $0) })
        #expect(byID[e1rmID]?.kind == AssessmentKind.e1RM.rawValue)
        #expect(byID[e1rmID]?.exerciseName == "Bench Press")
        #expect(byID[e1rmID]?.inputWeight == 120)
        #expect(byID[e1rmID]?.inputReps == 3)
        #expect(byID[pushupID]?.kind == AssessmentKind.pushupMax.rawValue)
        #expect(byID[pushupID]?.value == 42)

        let json = try DataExport.encodeJSON(export)
        let decoded = try DataExport.decodeJSON(json)
        #expect(decoded.assessments.count == 2)
    }

    @Test func buildExportWithPreferencesRoundTrip() throws {
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
            oneRepMaxFormula: "brzycki", restSeconds: 120,
            warmupMinutes: 5, cooldownMinutes: 5,
            autoStartRest: true, idleTimeoutMinutes: 3,
            plateRounding: true, autoSaveHealth: false,
            workoutSounds: true, preWorkoutCountdown: 5,
            trainingGoal: "strength", experienceLevel: "intermediate",
            favoriteRoutineIDs: ["preset-531", "preset-5x5"],
            schedulePreferences: CoachSchedulePreferences(allowsTwoADays: false),
            coachProfile: profile)

        let export = try WorkoutRepository.buildExport(ctx, preferences: prefs)
        #expect(export.preferences != nil)
        #expect(export.preferences?.unit == "pounds")
        #expect(export.preferences?.prRule == "heaviestSet")
        #expect(export.preferences?.coachProfile?.aerobicPreferences.first?.score == 5)
        #expect(export.preferences?.favoriteRoutineIDs == ["preset-531", "preset-5x5"])

        let json = try DataExport.encodeJSON(export)
        let decoded = try DataExport.decodeJSON(json)
        #expect(decoded.preferences?.unit == "pounds")
        #expect(decoded.preferences?.oneRepMaxFormula == "brzycki")
        #expect(decoded.preferences?.coachProfile?.strengthPreferences.first?.exerciseName == "Bench Press")
        #expect(decoded.preferences?.coachProfile?.avoidedTags == ["boring"])
    }

    @Test func fullRoundTripReExportMatches() throws {
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
            schedulePreferences: CoachSchedulePreferences())

        let exportA = try WorkoutRepository.buildExport(ctxA, preferences: prefs)
        let json = try DataExport.encodeJSON(exportA)
        let decoded = try DataExport.decodeJSON(json)

        // Merge into fresh store.
        let ctxB = try makeStore()
        let added = try WorkoutRepository.merge(decoded, in: ctxB)
        #expect(added == 3, "1 session + 1 cardio + 1 assessment")

        var profile = CoachPreferenceProfile.empty
        profile.aerobicPreferences = [
            AerobicPreference(intent: .moderateAerobic, modality: .run, score: 2, updatedAt: now)
        ]
        let prefsB = ExportPreferences(unit: "pounds", coachProfile: profile)
        let exportB = try WorkoutRepository.buildExport(ctxB,
                                                        coachPreferences: profile.exportDTO,
                                                        preferences: prefsB)

        // Core data must match (ignore exportedAt which differs).
        #expect(exportB.sessions.count == exportA.sessions.count)
        #expect(exportB.cardio.count == exportA.cardio.count)
        #expect(exportB.assessments.count == exportA.assessments.count)

        // Compare sessions by id.
        let sessionMapA = Dictionary(uniqueKeysWithValues: exportA.sessions.map { ($0.id, $0) })
        let sessionMapB = Dictionary(uniqueKeysWithValues: exportB.sessions.map { ($0.id, $0) })
        for (id, a) in sessionMapA {
            guard let b = sessionMapB[id] else { Issue.record("Session \(id) missing in re-export"); continue }
            #expect(b.title == a.title)
            #expect(b.planKey == a.planKey)
            #expect(b.sets.count == a.sets.count)
            #expect(b.warmupSeconds == a.warmupSeconds)
        }

        // Cardio must match.
        let cardioMapA = Dictionary(uniqueKeysWithValues: exportA.cardio.map { ($0.id, $0) })
        let cardioMapB = Dictionary(uniqueKeysWithValues: exportB.cardio.map { ($0.id, $0) })
        for (id, a) in cardioMapA {
            guard let b = cardioMapB[id] else { Issue.record("Cardio \(id) missing in re-export"); continue }
            #expect(b.hrSamples?.count == a.hrSamples?.count)
            #expect(b.distanceMeters == a.distanceMeters)
        }

        // Assessments must match.
        #expect(exportB.assessments == exportA.assessments)
    }

    @Test func emptyExportEncodesToValidJSON() throws {
        let empty = CadenceExport(sessions: [])
        let json = try DataExport.encodeJSON(empty)
        let str = String(data: json, encoding: .utf8)!
        #expect(str.contains("\"sessions\""))
        #expect(str.contains("\"cardio\""))
        #expect(str.contains("\"version\""))
        // Must be parseable back.
        let decoded = try DataExport.decodeJSON(json)
        #expect(decoded.sessions.count == 0)
        #expect(decoded.version == CadenceExport.currentVersion)
    }

    @Test func mergeDoesNotLoseSessionMetadata() throws {
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
        #expect(sessions.count == 1)
        let s = sessions[0]
        #expect(s.title == "Upper")
        #expect(s.planKey == "preset-531")
        #expect(s.templateName == "5/3/1 OHP")
        #expect(s.warmupSeconds == 300)
        #expect(s.cooldownSeconds == 300)
        #expect(s.prescribedLoadKg == 67.5)
        #expect(s.plannedExerciseNames == ["Overhead Press"])
        #expect(s.plannedRepLadder == [5, 3, 1])
        #expect(s.notes == "Deload")
        #expect(s.isLogged)
        #expect(s.activePartnerIDs == ["partner-uuid-1"])
        #expect(s.orderedSets.count == 1)
        #expect(s.orderedSets[0].weight == 65)
    }

    // MARK: - Task.detached export (off-main-thread) → import → re-export

    /// Validates the exact pattern ExportView now uses: spawn a detached task with
    /// the ModelContainer, create a fresh ModelContext inside it, build the export
    /// AND encode it — all off the main thread — then merge into a fresh store and
    /// assert the lossless round-trip. This catches any Sendable/isolation issue
    /// that the prior @ModelActor approach may have masked.
    @Test func detachedExportThenImportThenReExportIsLossless() async throws {
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
            unit: "kilograms", prRule: "heaviestSet",
            trainingGoal: "strength", experienceLevel: "intermediate",
            schedulePreferences: CoachSchedulePreferences(),
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
        #expect(decoded.version == CadenceExport.currentVersion)
        #expect(decoded.sessions.count == 2)
        #expect(decoded.cardio.count == 1)
        #expect(decoded.assessments.count == 1)
        #expect(decoded.preferences?.unit == "kilograms")
        #expect(decoded.preferences?.prRule == "heaviestSet")
        #expect(decoded.preferences?.coachProfile?.aerobicPreferences.first?.score == 5)

        // Phase 3: merge into a fresh store, then export again from it — drill into
        // every facet to prove nothing was lost.
        let containerB = try CadenceStore.makeModelContainer(inMemory: true)
        let ctxB = ModelContext(containerB)
        let added = try WorkoutRepository.merge(decoded, in: ctxB)
        #expect(added == 4, "2 sessions + 1 cardio + 1 assessment")

        let reExported = try WorkoutRepository.buildExport(ctxB,
            preferences: ExportPreferences(unit: "kilograms"))
        #expect(reExported.sessions.count == 2)
        #expect(reExported.cardio.count == 1)
        #expect(reExported.assessments.count == 1)

        // Verify strength sessions by title.
        let titles = Set(reExported.sessions.map(\.title))
        #expect(titles.contains("Leg Day"))
        #expect(titles.contains("Push Day"))

        // Verify set-level data survived.
        let allSets = reExported.sessions.flatMap(\.sets)
        #expect(allSets.count == 4)
        #expect(allSets.contains(where: { $0.exerciseName == "Back Squat" && $0.weightKg == 140 }))
        #expect(allSets.contains(where: { $0.exerciseName == "Bench Press" && $0.weightKg == 105 }))

        // Verify cardio HR/route samples survived the full tour.
        let reCardio = reExported.cardio.first
        #expect(reCardio != nil)
        #expect(reCardio?.hrSamples?.count == 2)
        #expect(reCardio?.routeSamples?.count == 1)
        #expect(reCardio?.notes == "tempo")

        // Verify assessment.
        #expect(reExported.assessments.first?.value == 42)
    }

    // MARK: - Per-performer prescriptions (field test 2026-08-18 #4)

    @Test func exportRoundTripsPerformerPrescriptions() throws {
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

        #expect(decoded.sessions.first?.plannedPerformerPrescriptions == performerPlans)
    }

    @Test func exportImportPreservesUnifiedPlanSourceIDs() throws {
        let planSessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000301")!
        let sourceItemID = UUID(uuidString: "00000000-0000-0000-0000-000000000302")!
        let sourceSetID = UUID(uuidString: "00000000-0000-0000-0000-000000000303")!
        let prescription = PlannedExercisePrescription(
            sourceItemID: sourceItemID,
            exerciseKey: "bench_press",
            exerciseName: "Bench Press",
            sets: [PlannedSetPrescription(
                sourceSetID: sourceSetID, targetReps: 5, targetWeightKg: 80,
                targetLoadMode: "absolute", restSeconds: 150)])
        let original = CadenceExport(sessions: [ExportSession(
            id: UUID(), title: "Upper", date: Date(timeIntervalSince1970: 1_700_000_000),
            notes: nil, sets: [], plannedPrescriptions: [prescription],
            planSessionID: planSessionID)])

        let decoded = try DataExport.decodeJSON(DataExport.encodeJSON(original))

        #expect(decoded.sessions.first?.planSessionID == planSessionID)
        #expect(decoded.sessions.first?.plannedPrescriptions?.first?.sourceItemID == sourceItemID)
        #expect(decoded.sessions.first?.plannedPrescriptions?.first?.sets.first?.sourceSetID == sourceSetID)
    }

    @Test func importOfALegacyExportWithoutPerformerPrescriptionsSucceeds() throws {
        // A pre-Phase-9 export simply has no such key: the encoder omits a nil
        // optional entirely, which is exactly the legacy on-disk shape.
        let legacy = CadenceExport(sessions: [ExportSession(
            id: UUID(), title: "Push Day", date: Date(timeIntervalSince1970: 1_700_000_000),
            notes: nil, sets: [],
            plannedPrescriptions: [PlannedExercisePrescription(
                exerciseName: "Bench Press",
                sets: [PlannedSetPrescription(targetReps: 5, targetWeightKg: 100)])])])
        let data = try DataExport.encodeJSON(legacy)
        #expect(!String(decoding: data, as: UTF8.self).contains("plannedPerformerPrescriptions"),
                       "The legacy fixture must not carry the new key at all")

        let decoded = try DataExport.decodeJSON(data)

        #expect(decoded.sessions.count == 1)
        #expect(decoded.sessions.first?.plannedPerformerPrescriptions == nil,
                     "An export written before this field must decode with it absent")
        #expect(decoded.sessions.first?.plannedPrescriptions?.first?.sets.first?.targetReps == 5,
                       "and the owner's plan must survive untouched")
    }
}
#endif
