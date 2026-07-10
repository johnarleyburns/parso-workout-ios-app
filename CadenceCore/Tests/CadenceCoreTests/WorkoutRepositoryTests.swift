import XCTest
import SwiftData
@testable import CadenceCore

@MainActor
final class WorkoutRepositoryTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let container = try CadenceStore.makeModelContainer(inMemory: true)
        return ModelContext(container)
    }

    func testSeedStarterLibrary() throws {
        let ctx = try makeContext()
        let didSeed = try WorkoutRepository.seedStarterLibraryIfNeeded(ctx)
        XCTAssertTrue(didSeed)
        XCTAssertEqual(try WorkoutRepository.allExercises(ctx).count, ExerciseLibrary.starter.count)
        // idempotent
        XCTAssertFalse(try WorkoutRepository.seedStarterLibraryIfNeeded(ctx))
        XCTAssertEqual(try WorkoutRepository.allExercises(ctx).count, ExerciseLibrary.starter.count)
    }

    func testSearchExercises() throws {
        let ctx = try makeContext()
        try WorkoutRepository.seedStarterLibraryIfNeeded(ctx)
        let bench = try WorkoutRepository.searchExercises("bench", in: ctx)
        XCTAssertTrue(bench.contains { $0.name == "Bench Press" })
        XCTAssertFalse(bench.contains { $0.name == "Deadlift" })
    }

    func testFindOrCreateExerciseDeduplicates() throws {
        let ctx = try makeContext()
        let a = try WorkoutRepository.findOrCreateExercise(named: "Zercher Squat", in: ctx)
        let b = try WorkoutRepository.findOrCreateExercise(named: "zercher squat", in: ctx)
        XCTAssertEqual(a.id, b.id)
        XCTAssertTrue(a.isCustom)
    }

    func testAddSetAssignsIncrementingOrder() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(in: ctx)
        let ex = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: ex, weightKg: 100, reps: 5, in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: ex, weightKg: 100, reps: 5, in: ctx)
        XCTAssertEqual(session.orderedSets.map(\.order), [0, 1])
    }

    func testLastTimeSets() throws {
        let ctx = try makeContext()
        let ex = try WorkoutRepository.findOrCreateExercise(named: "Squat", in: ctx)

        let old = try WorkoutRepository.createSession(date: Date(timeIntervalSince1970: 1000), in: ctx)
        _ = try WorkoutRepository.addSet(to: old, exercise: ex, weightKg: 100, reps: 5, in: ctx)

        let mid = try WorkoutRepository.createSession(date: Date(timeIntervalSince1970: 5000), in: ctx)
        _ = try WorkoutRepository.addSet(to: mid, exercise: ex, weightKg: 110, reps: 5, in: ctx)
        _ = try WorkoutRepository.addSet(to: mid, exercise: ex, weightKg: 110, reps: 4, in: ctx)

        let today = try WorkoutRepository.createSession(date: Date(timeIntervalSince1970: 9000), in: ctx)
        let last = WorkoutRepository.lastTimeSets(for: ex, excluding: today)
        XCTAssertEqual(last.count, 2)
        XCTAssertEqual(last.map(\.weight), [110, 110])
        XCTAssertEqual(last.map(\.reps), [5, 4])
    }

    func testCurrentPRAndWouldBePR() throws {
        let ctx = try makeContext()
        let ex = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)
        let s1 = try WorkoutRepository.createSession(date: Date(timeIntervalSince1970: 1000), in: ctx)
        _ = try WorkoutRepository.addSet(to: s1, exercise: ex, weightKg: 100, reps: 5, in: ctx)

        XCTAssertEqual(WorkoutRepository.currentPR(for: ex, rule: .topWeight, formula: .epley), 100)

        let today = try WorkoutRepository.createSession(date: Date(timeIntervalSince1970: 9000), in: ctx)
        XCTAssertTrue(WorkoutRepository.wouldBePR(exercise: ex, weightKg: 105, reps: 5, isWarmup: false,
                                                  rule: .topWeight, formula: .epley, excluding: today))
        XCTAssertFalse(WorkoutRepository.wouldBePR(exercise: ex, weightKg: 95, reps: 5, isWarmup: false,
                                                   rule: .topWeight, formula: .epley, excluding: today))
    }

    func testUpdateAndDeleteSet() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(in: ctx)
        let ex = try WorkoutRepository.findOrCreateExercise(named: "Row", in: ctx)
        let set = try WorkoutRepository.addSet(to: session, exercise: ex, weightKg: 60, reps: 8, in: ctx)

        try WorkoutRepository.updateSet(set, weightKg: 65, reps: 10, in: ctx)
        XCTAssertEqual(set.weight, 65)
        XCTAssertEqual(set.reps, 10)

        try WorkoutRepository.deleteSet(set, in: ctx)
        XCTAssertEqual(session.orderedSets.count, 0)
    }

    func testTemplatesAndStartSession() throws {
        let ctx = try makeContext()
        let t = try WorkoutRepository.createTemplate(name: "Push Day",
            exercises: [("Bench Press", 3, 5), ("Overhead Press", 3, 8)], in: ctx)
        XCTAssertEqual(t.orderedExercises.count, 2)

        let session = try WorkoutRepository.startSession(from: t, in: ctx)
        XCTAssertEqual(session.title, "Push Day")
        XCTAssertEqual(session.templateName, "Push Day")
        // exercises resolved into the library
        let names = try WorkoutRepository.allExercises(ctx).map(\.name)
        XCTAssertTrue(names.contains("Bench Press"))
        XCTAssertTrue(names.contains("Overhead Press"))
    }

    func testIngestDeduplicatesByHKUUID() throws {
        let ctx = try makeContext()
        let hkID = UUID()
        let w = IngestedWorkout(id: hkID, type: .run, start: Date(timeIntervalSince1970: 0),
                                end: Date(timeIntervalSince1970: 1800), distanceMeters: 5000,
                                hrSamples: [HRSamplePoint(t: 0, bpm: 120), HRSamplePoint(t: 60, bpm: 140)],
                                importedKind: .running)
        XCTAssertEqual(try WorkoutRepository.ingest([w], in: ctx), 1)
        XCTAssertEqual(try WorkoutRepository.ingest([w], in: ctx), 0) // dup skipped
        let all = try WorkoutRepository.allCardio(ctx)
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].orderedHRSamples.count, 2)
    }

    func testSaveRecordedCardioComputesHRAndLinksHK() throws {
        let ctx = try makeContext()
        let hkID = UUID()
        let summary = CardioWorkoutSummary(
            id: UUID(), type: .run, start: Date(timeIntervalSince1970: 0),
            end: Date(timeIntervalSince1970: 1800), distanceMeters: 5000, activeEnergyKcal: 400,
            hrSamples: [HRSamplePoint(t: 0, bpm: 120), HRSamplePoint(t: 60, bpm: 160)],
            route: [LocationFix(t: 0, lat: 1, lon: 1), LocationFix(t: 1, lat: 1.001, lon: 1)])
        let c = try WorkoutRepository.saveRecordedCardio(summary, source: .iphone,
                                                         healthKitWorkoutUUID: hkID, in: ctx)
        XCTAssertEqual(c.avgHeartRate, 140) // (120+160)/2
        XCTAssertEqual(c.maxHeartRate, 160)
        XCTAssertEqual(c.healthKitWorkoutUUID, hkID)
        XCTAssertEqual(c.orderedHRSamples.count, 2)
        XCTAssertEqual(c.orderedRouteSamples.count, 2)

        // A later HealthKit ingest of the same workout must not duplicate it.
        let ingestSame = IngestedWorkout(id: hkID, type: .run,
                                         start: summary.start, end: summary.end,
                                         importedKind: .running)
        XCTAssertEqual(try WorkoutRepository.ingest([ingestSame], in: ctx), 0)
        XCTAssertEqual(try WorkoutRepository.allCardio(ctx).count, 1)
    }

    // Feedback batch 6 item 3 — a manually logged cardio workout lands in history
    // identically to a recorded one, but flagged isLogged with its custom title.
    func testSaveLoggedCardioFlagsAndTitles() throws {
        let ctx = try makeContext()
        let start = Date(timeIntervalSince1970: 1000)
        let c = try WorkoutRepository.saveLoggedCardio(
            type: .other, start: start, durationSeconds: 1500,
            distanceMeters: 2000, customTitle: "  Rowing  ", in: ctx)
        XCTAssertTrue(c.isLogged)
        XCTAssertEqual(c.customTitle, "Rowing")          // trimmed
        XCTAssertEqual(c.displayTitle, "Rowing")
        XCTAssertEqual(c.duration, 1500)
        XCTAssertEqual(c.distance, 2000)
        XCTAssertEqual(try WorkoutRepository.allCardio(ctx).count, 1)
    }

    // A blank custom title falls back to the type's display name.
    func testSaveLoggedCardioBlankTitleFallsBack() throws {
        let ctx = try makeContext()
        let c = try WorkoutRepository.saveLoggedCardio(
            type: .run, start: Date(timeIntervalSince1970: 0),
            durationSeconds: 600, customTitle: "   ", in: ctx)
        XCTAssertNil(c.customTitle)
        XCTAssertEqual(c.displayTitle, "Run")
        XCTAssertTrue(c.isLogged)
    }

    // Manual strength logging (feedback batch 7 follow-up) — a logged strength
    // session flags isLogged, keeps its back-dated date, and surfaces in unified
    // history identically to a live one; logging from a preset pre-loads its
    // movements and flags isLogged too.
    func testCreateLoggedStrengthSessionFlagsAndSurfaces() throws {
        let ctx = try makeContext()
        let date = Date(timeIntervalSince1970: 5000)
        let s = try WorkoutRepository.createSession(title: "Workout", date: date,
                                                    isLogged: true, in: ctx)
        XCTAssertTrue(s.isLogged)
        XCTAssertEqual(s.date, date)
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)
        _ = try WorkoutRepository.addSet(to: s, exercise: bench, weightKg: 100, reps: 5,
                                         completedAt: date, in: ctx)
        let history = try WorkoutRepository.unifiedHistory(ctx)
        let logged = history.compactMap { if case let .strength(ws) = $0 { return ws } else { return nil } }
        XCTAssertTrue(logged.contains { $0.id == s.id && $0.isLogged })
    }

    func testStartLoggedPlanSessionPreloadsMovements() throws {
        let ctx = try makeContext()
        let preset = try XCTUnwrap(PlanCatalog.plan(forKey: "preset-5x5-1a"))
        let s = try WorkoutRepository.startSession(from: preset,
                                                   date: Date(timeIntervalSince1970: 100),
                                                   isLogged: true, in: ctx)
        XCTAssertTrue(s.isLogged)
        XCTAssertEqual(s.planKey, "preset-5x5-1a")
        XCTAssertTrue(s.plannedExerciseNames.contains("Back Squat"))
        XCTAssertTrue(s.title.localizedCaseInsensitiveContains("5×5"))
    }

    // Batch 8 — rank past workouts by how many missing body parts they cover.
    func testWorkoutsByMissingCoverageRanksByCoveredCount() throws {
        let ctx = try makeContext()
        let pulldown = try WorkoutRepository.findOrCreateExercise(named: "Lat Pulldown", in: ctx) // back
        let calf = try WorkoutRepository.findOrCreateExercise(named: "Standing Calf Raise", in: ctx) // calves
        let curl = try WorkoutRepository.findOrCreateExercise(named: "Dumbbell Curl", in: ctx) // biceps

        // Session A covers back + calves; Session B covers only biceps (not missing).
        let a = try WorkoutRepository.createSession(date: Date(timeIntervalSince1970: 2000), in: ctx)
        _ = try WorkoutRepository.addSet(to: a, exercise: pulldown, weightKg: 50, reps: 10, in: ctx)
        _ = try WorkoutRepository.addSet(to: a, exercise: calf, weightKg: 60, reps: 12, in: ctx)
        let b = try WorkoutRepository.createSession(date: Date(timeIntervalSince1970: 1000), in: ctx)
        _ = try WorkoutRepository.addSet(to: b, exercise: curl, weightKg: 15, reps: 10, in: ctx)

        let ranked = WorkoutRepository.workoutsByMissingCoverage(
            try WorkoutRepository.allSessions(ctx), missing: [.back, .calves, .chest])
        XCTAssertEqual(ranked.first?.session.id, a.id, "the session covering the most missing parts ranks first")
        XCTAssertEqual(Set(ranked.first?.covered ?? []), Set([.back, .calves]))
        XCTAssertFalse(ranked.contains { $0.session.id == b.id }, "a session covering no missing part is excluded")
    }

    // Batch 8 — a distance goal persists through saveRecordedCardio.
    func testRecordedCardioCarriesDistanceGoal() throws {
        let ctx = try makeContext()
        let summary = CardioWorkoutSummary(
            id: UUID(), type: .run, start: Date(timeIntervalSince1970: 0),
            end: Date(timeIntervalSince1970: 1800), distanceMeters: 5200,
            targetDistanceMeters: 5000)
        let c = try WorkoutRepository.saveRecordedCardio(summary, source: .iphone,
                                                         healthKitWorkoutUUID: nil, in: ctx)
        XCTAssertEqual(c.targetDistance, 5000)
        let progress = CardioMath.goalProgress(distanceMeters: c.distance ?? 0, goalMeters: c.targetDistance)
        XCTAssertEqual(progress?.fraction, 1, "5.2 km of a 5 km goal is complete (clamped)")
        XCTAssertEqual(progress?.remainingMeters, 0)
    }

    func testGoalProgressNilWhenNoGoal() {
        XCTAssertNil(CardioMath.goalProgress(distanceMeters: 1000, goalMeters: nil))
        let p = CardioMath.goalProgress(distanceMeters: 2500, goalMeters: 5000)
        XCTAssertEqual(p?.fraction ?? 0, 0.5, accuracy: 0.001)
        XCTAssertEqual(p?.remainingMeters ?? 0, 2500, accuracy: 0.001)
    }

    func testRecentPRs() throws {
        let ctx = try makeContext()
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)
        let squat = try WorkoutRepository.findOrCreateExercise(named: "Squat", in: ctx)
        let s = try WorkoutRepository.createSession(date: Date(timeIntervalSince1970: 1000), in: ctx)
        _ = try WorkoutRepository.addSet(to: s, exercise: bench, weightKg: 100, reps: 5,
                                         completedAt: Date(timeIntervalSince1970: 1000), in: ctx)
        _ = try WorkoutRepository.addSet(to: s, exercise: squat, weightKg: 140, reps: 5,
                                         completedAt: Date(timeIntervalSince1970: 2000), in: ctx)
        let prs = try WorkoutRepository.recentPRs(ctx, rule: .topWeight, formula: .epley)
        XCTAssertEqual(prs.count, 2)
        XCTAssertEqual(prs.first?.exerciseName, "Squat") // most recent first
    }

    func testTrendSeriesBestPerDay() throws {
        let ctx = try makeContext()
        let ex = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)
        let d1 = try WorkoutRepository.createSession(date: Date(timeIntervalSince1970: 0), in: ctx)
        _ = try WorkoutRepository.addSet(to: d1, exercise: ex, weightKg: 100, reps: 5,
                                         completedAt: Date(timeIntervalSince1970: 0), in: ctx)
        _ = try WorkoutRepository.addSet(to: d1, exercise: ex, weightKg: 110, reps: 5,
                                         completedAt: Date(timeIntervalSince1970: 100), in: ctx)
        let d2 = try WorkoutRepository.createSession(date: Date(timeIntervalSince1970: 200_000), in: ctx)
        _ = try WorkoutRepository.addSet(to: d2, exercise: ex, weightKg: 105, reps: 5,
                                         completedAt: Date(timeIntervalSince1970: 200_000), in: ctx)
        let series = WorkoutRepository.trendSeries(for: ex, rule: .topWeight, formula: .epley)
        XCTAssertEqual(series.count, 2)        // two days
        XCTAssertEqual(series[0].value, 110)   // best of day 1
        XCTAssertEqual(series[1].value, 105)
    }

    func testPRTimelineProgressiveOnly() throws {
        let ctx = try makeContext()
        let ex = try WorkoutRepository.findOrCreateExercise(named: "Squat", in: ctx)
        let s = try WorkoutRepository.createSession(in: ctx)
        // 100 (PR), 95 (no), 110 (PR), 110 (tie, no)
        let weights = [100.0, 95, 110, 110]
        for (i, w) in weights.enumerated() {
            _ = try WorkoutRepository.addSet(to: s, exercise: ex, weightKg: w, reps: 5,
                                             completedAt: Date(timeIntervalSince1970: TimeInterval(i)), in: ctx)
        }
        let timeline = WorkoutRepository.prTimeline(for: ex, rule: .topWeight, formula: .epley)
        XCTAssertEqual(timeline.map(\.value), [100, 110])
    }

    func testTrainingDays() throws {
        let ctx = try makeContext()
        _ = try WorkoutRepository.createSession(date: Date(timeIntervalSince1970: 0), in: ctx)
        _ = try WorkoutRepository.createSession(date: Date(timeIntervalSince1970: 3600), in: ctx) // same day
        _ = try WorkoutRepository.createSession(date: Date(timeIntervalSince1970: 200_000), in: ctx)
        let days = try WorkoutRepository.trainingDays(ctx, calendar: {
            var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
        }())
        XCTAssertEqual(days.count, 2)
    }

    func testExportImportRoundTrip() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(title: "Push", in: ctx)
        let ex = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", category: .push, in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: ex, weightKg: 100, reps: 5, rpe: 8, in: ctx)

        let export = try WorkoutRepository.buildExport(ctx)
        XCTAssertEqual(export.sessions.count, 1)
        XCTAssertEqual(export.sessions[0].sets.count, 1)

        // merge into a fresh store
        let ctx2 = try makeContext()
        let added = try WorkoutRepository.merge(export, in: ctx2)
        XCTAssertEqual(added, 1)
        let sessions = try WorkoutRepository.allSessions(ctx2)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].orderedSets.first?.weight, 100)
        // merging again is a no-op (dedup by id)
        XCTAssertEqual(try WorkoutRepository.merge(export, in: ctx2), 0)
    }

    func testApplyParsedSessions() throws {
        let ctx = try makeContext()
        let parsed = GmailImporter.parse("# Push 2024-01-15\nBench Press 100 3x5").sessions
        let count = try WorkoutRepository.apply(parsed, in: ctx)
        XCTAssertEqual(count, 1)
        let sessions = try WorkoutRepository.allSessions(ctx)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].orderedSets.count, 3)
        XCTAssertEqual(sessions[0].title, "Push")
    }

    func testReassignAndDeleteExercise() throws {
        let ctx = try makeContext()
        let custom = Exercise(name: "rotary torso", category: .core, isCustom: true)
        let builtIn = Exercise(name: "Torso Rotation", isCustom: false, primaryMuscles: ["abs"])
        ctx.insert(custom); ctx.insert(builtIn)
        let session = try WorkoutRepository.createSession(title: "Core Day", in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: custom, weightKg: 0, reps: 15,
                                         completedAt: Date(timeIntervalSince1970: 1_750_000_000), in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: custom, weightKg: 0, reps: 12,
                                         completedAt: Date(timeIntervalSince1970: 1_750_000_000), in: ctx)
        session.plannedExerciseNames = ["rotary torso"]
        try ctx.save()

        let moved = try WorkoutRepository.reassignAndDeleteExercise(from: custom, into: builtIn, in: ctx)
        XCTAssertEqual(moved, 2)
        let sessions = try WorkoutRepository.allSessions(ctx)
        XCTAssertEqual(sessions.count, 1)
        for set in sessions[0].orderedSets {
            XCTAssertEqual(set.exercise?.name, "Torso Rotation")
        }
        let remaining = try WorkoutRepository.allExercises(ctx)
        XCTAssertNil(remaining.first { $0.name == "rotary torso" })
    }
}
