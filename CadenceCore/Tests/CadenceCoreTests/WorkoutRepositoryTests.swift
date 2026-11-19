#if canImport(SwiftData)
import Foundation
import Testing
import SwiftData
@testable import CadenceCore

@MainActor
struct WorkoutRepositoryTests {

    private func makeContext() throws -> ModelContext {
        let container = try CadenceStore.makeModelContainer(inMemory: true)
        return ModelContext(container)
    }

    @Test func seedStarterLibrary() throws {
        let ctx = try makeContext()
        let didSeed = try WorkoutRepository.seedStarterLibraryIfNeeded(ctx)
        #expect(didSeed)
        #expect(try WorkoutRepository.allExercises(ctx).count == ExerciseLibrary.starter.count)
        // idempotent
        #expect(!(try WorkoutRepository.seedStarterLibraryIfNeeded(ctx)))
        #expect(try WorkoutRepository.allExercises(ctx).count == ExerciseLibrary.starter.count)
    }

    @Test func searchExercises() throws {
        let ctx = try makeContext()
        try WorkoutRepository.seedStarterLibraryIfNeeded(ctx)
        let bench = try WorkoutRepository.searchExercises("bench", in: ctx)
        #expect(bench.contains { $0.name == "Bench Press" })
        #expect(!bench.contains { $0.name == "Deadlift" })
    }

    @Test func findOrCreateExerciseDeduplicates() throws {
        let ctx = try makeContext()
        let a = try WorkoutRepository.findOrCreateExercise(named: "Garage Custom Lift", in: ctx)
        let b = try WorkoutRepository.findOrCreateExercise(named: "garage custom lift", in: ctx)
        #expect(a.id == b.id)
        #expect(a.isCustom)
    }

    @Test func addSetAssignsIncrementingOrder() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(in: ctx)
        let ex = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: ex, weightKg: 100, reps: 5, in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: ex, weightKg: 100, reps: 5, in: ctx)
        #expect(session.orderedSets.map(\.order) == [0, 1])
    }

    @Test func adHocExerciseDoesNotInheritLegacyPlan() throws {
        let ctx = try makeContext()
        let squat = try WorkoutRepository.findOrCreateExercise(named: "Back Squat", in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)
        let session = try WorkoutRepository.createSession(date: Date(), in: ctx)
        session.plannedExerciseNames = ["Back Squat"]
        session.plannedRepLadder = [6, 6, 6]
        session.prescribedLoadKg = 88.5
        #expect(session.explicitPlannedSets(forPerformerID: nil, exerciseName: "Back Squat") != nil)

        #expect(try WorkoutRepository.addAdHocExercise(bench, to: session, in: ctx))
        #expect(session.explicitPlannedSets(forPerformerID: nil, exerciseName: "Bench Press") == nil)
        #expect(session.explicitPlannedSets(forPerformerID: nil, exerciseName: "Back Squat")?.first?.targetWeightKg == 88.5)
        #expect(session.plannedExerciseNames.contains("Bench Press"))
        #expect(!(try WorkoutRepository.addAdHocExercise(bench, to: session, in: ctx)))
        #expect(session.plannedExerciseNames.count == 2)
        _ = squat
    }

    @Test func lastWorkingSetIsLiteralLastNonWarmupSet() throws {
        let ctx = try makeContext()
        let ex = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)
        let old = try WorkoutRepository.createSession(date: Date(timeIntervalSince1970: 1000), in: ctx)
        _ = try WorkoutRepository.addSet(to: old, exercise: ex, weightKg: 56.699, reps: 8, in: ctx)
        _ = try WorkoutRepository.addSet(to: old, exercise: ex, weightKg: 20, reps: 10, isWarmup: true, in: ctx)
        let today = try WorkoutRepository.createSession(date: Date(timeIntervalSince1970: 9000), in: ctx)
        let last = WorkoutRepository.lastWorkingSet(for: ex, performedBy: nil, excluding: today)
        #expect(last?.reps == 8)
        #expect(abs((last?.weight ?? 0) - 56.699) <= 0.0001)
    }

    @Test func lastTimeSets() throws {
        let ctx = try makeContext()
        let ex = try WorkoutRepository.findOrCreateExercise(named: "Squat", in: ctx)

        let old = try WorkoutRepository.createSession(date: Date(timeIntervalSince1970: 1000), in: ctx)
        _ = try WorkoutRepository.addSet(to: old, exercise: ex, weightKg: 100, reps: 5, in: ctx)

        let mid = try WorkoutRepository.createSession(date: Date(timeIntervalSince1970: 5000), in: ctx)
        _ = try WorkoutRepository.addSet(to: mid, exercise: ex, weightKg: 110, reps: 5, in: ctx)
        _ = try WorkoutRepository.addSet(to: mid, exercise: ex, weightKg: 110, reps: 4, in: ctx)

        let today = try WorkoutRepository.createSession(date: Date(timeIntervalSince1970: 9000), in: ctx)
        let last = WorkoutRepository.lastTimeSets(for: ex, excluding: today)
        #expect(last.count == 2)
        #expect(last.map(\.weight) == [110, 110])
        #expect(last.map(\.reps) == [5, 4])
    }

    @Test func currentPRAndWouldBePR() throws {
        let ctx = try makeContext()
        let ex = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)
        let s1 = try WorkoutRepository.createSession(date: Date(timeIntervalSince1970: 1000), in: ctx)
        _ = try WorkoutRepository.addSet(to: s1, exercise: ex, weightKg: 100, reps: 5, in: ctx)

        #expect(WorkoutRepository.currentPR(for: ex, rule: .topWeight, formula: .epley) == 100)

        let today = try WorkoutRepository.createSession(date: Date(timeIntervalSince1970: 9000), in: ctx)
        #expect(WorkoutRepository.wouldBePR(exercise: ex, weightKg: 105, reps: 5, isWarmup: false,
                                                  rule: .topWeight, formula: .epley, excluding: today))
        #expect(!WorkoutRepository.wouldBePR(exercise: ex, weightKg: 95, reps: 5, isWarmup: false,
                                                   rule: .topWeight, formula: .epley, excluding: today))
    }

    @Test func updateAndDeleteSet() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(in: ctx)
        let ex = try WorkoutRepository.findOrCreateExercise(named: "Row", in: ctx)
        let set = try WorkoutRepository.addSet(to: session, exercise: ex, weightKg: 60, reps: 8, in: ctx)

        try WorkoutRepository.updateSet(set, weightKg: 65, reps: 10, in: ctx)
        #expect(set.weight == 65)
        #expect(set.reps == 10)

        try WorkoutRepository.deleteSet(set, in: ctx)
        #expect(session.orderedSets.count == 0)
    }

    @Test func templatesAndStartSession() throws {
        let ctx = try makeContext()
        let t = try WorkoutRepository.createTemplate(name: "Push Day",
            exercises: [("Bench Press", 3, 5), ("Overhead Press", 3, 8)], in: ctx)
        #expect(t.orderedExercises.count == 2)

        let session = try WorkoutRepository.startSession(from: t, in: ctx)
        #expect(session.title == "Push Day")
        #expect(session.templateName == "Push Day")
        // exercises resolved into the library
        let names = try WorkoutRepository.allExercises(ctx).map(\.name)
        #expect(names.contains("Bench Press"))
        #expect(names.contains("Overhead Press"))
    }

    @Test func ingestDeduplicatesByHKUUID() throws {
        let ctx = try makeContext()
        let hkID = UUID()
        let w = IngestedWorkout(id: hkID, type: .run, start: Date(timeIntervalSince1970: 0),
                                end: Date(timeIntervalSince1970: 1800), distanceMeters: 5000,
                                hrSamples: [HRSamplePoint(t: 0, bpm: 120), HRSamplePoint(t: 60, bpm: 140)],
                                routeSamples: [LocationFix(t: 0, lat: 37, lon: -122),
                                                LocationFix(t: 60, lat: 37.001, lon: -122.001)],
                                importedKind: .running)
        #expect(try WorkoutRepository.ingest([w], in: ctx) == 1)
        #expect(try WorkoutRepository.ingest([w], in: ctx) == 0) // dup skipped
        let all = try WorkoutRepository.allCardio(ctx)
        #expect(all.count == 1)
        #expect(all[0].orderedHRSamples.count == 2)
        #expect(all[0].orderedRouteSamples.count == 2)
    }

    @Test func watchCompletionIsIdempotentAndReconcilesLaterHealthKitImport() throws {
        let ctx = try makeContext()
        let start = Date(timeIntervalSince1970: 10_000)
        let completion = WatchCardioCompletion(type: .run, start: start,
                                               end: start.addingTimeInterval(600),
                                               distanceMeters: 1500,
                                               hrSamples: [HRSamplePoint(t: 10, bpm: 130)],
                                               avgHeartRate: 130, maxHeartRate: 130,
                                               gpsEnabled: true)
        #expect(try WorkoutRepository.ingest(completion, in: ctx))
        #expect(!(try WorkoutRepository.ingest(completion, in: ctx)))

        let hkWorkout = IngestedWorkout(id: UUID(), type: .run, start: start,
                                        end: start.addingTimeInterval(600),
                                        importedKind: .running)
        #expect(try WorkoutRepository.ingest([hkWorkout], in: ctx) == 0)
        let cardio = try #require(try WorkoutRepository.allCardio(ctx).first)
        #expect(cardio.healthKitWorkoutUUID == hkWorkout.id)
        #expect(cardio.orderedHRSamples.count == 1)
    }

    @Test func poolSwimCompletionStoresLapsDistanceAndDoesNotDuplicateHealthImport() throws {
        let context = try makeContext()
        let start = Date(timeIntervalSince1970: 10000)
        let value = WatchCardioCompletion(type: .swim, start: start,
            end: start.addingTimeInterval(600), distanceMeters: 500,
            swimmingLapCount: 10, poolLengthMeters: 50)
        #expect(try WorkoutRepository.ingest(value, in: context))
        #expect(!(try WorkoutRepository.ingest(value, in: context)))
        let imported = IngestedWorkout(id: UUID(), type: .swim, start: start,
            end: start.addingTimeInterval(600), distanceMeters: 500, importedKind: .swimming)
        #expect(try WorkoutRepository.ingest([imported], in: context) == 0)
        let saved = try #require(try WorkoutRepository.allCardio(context).first)
        #expect(saved.distance == 500)
        #expect(saved.laps == 10)
        #expect(saved.notes?.contains("50 m") == true)
        #expect(saved.healthKitWorkoutUUID == imported.id)
    }

    @Test func saveRecordedCardioComputesHRAndLinksHK() throws {
        let ctx = try makeContext()
        let hkID = UUID()
        let summary = CardioWorkoutSummary(
            id: UUID(), type: .run, start: Date(timeIntervalSince1970: 0),
            end: Date(timeIntervalSince1970: 1800), distanceMeters: 5000, activeEnergyKcal: 400,
            hrSamples: [HRSamplePoint(t: 0, bpm: 120), HRSamplePoint(t: 60, bpm: 160)],
            route: [LocationFix(t: 0, lat: 1, lon: 1), LocationFix(t: 1, lat: 1.001, lon: 1)])
        let c = try WorkoutRepository.saveRecordedCardio(summary, source: .iphone,
                                                         healthKitWorkoutUUID: hkID, in: ctx)
        #expect(c.avgHeartRate == 140) // (120+160)/2
        #expect(c.maxHeartRate == 160)
        #expect(c.healthKitWorkoutUUID == hkID)
        #expect(c.orderedHRSamples.count == 2)
        #expect(c.orderedRouteSamples.count == 2)

        // A later HealthKit ingest of the same workout must not duplicate it.
        let ingestSame = IngestedWorkout(id: hkID, type: .run,
                                         start: summary.start, end: summary.end,
                                         importedKind: .running)
        #expect(try WorkoutRepository.ingest([ingestSame], in: ctx) == 0)
        #expect(try WorkoutRepository.allCardio(ctx).count == 1)
    }

    @Test func healthRestoreReplacesOwnerSetsAndPreservesPartnerSets() throws {
        let ctx = try makeContext()
        let id = UUID()
        let start = Date(timeIntervalSince1970: 20_000)
        let session = WorkoutSession(id: id, title: "Old", date: start)
        ctx.insert(session)
        try ctx.save()
        let exercise = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)
        let partner = try WorkoutRepository.findOrCreatePerson(named: "Partner", in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: exercise, weightKg: 50, reps: 5,
                                         completedAt: start, in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: exercise, weightKg: 30, reps: 8,
                                         completedAt: start, performedBy: partner, in: ctx)
        try ctx.save()

        let replacementSet = CladironHealthBackup.SetPayload(
            id: UUID(), exerciseKey: "bench-press", exerciseName: "Bench Press",
            weightKg: 57, reps: 6, rpe: 8, isWarmup: false, usesBodyweight: false,
            note: nil, order: 0, completedAt: start.addingTimeInterval(60))
        let data = try JSONEncoder().encode([replacementSet])
        var metadata = CladironHealthBackup.baseMetadata(id: id, updatedAt: start.addingTimeInterval(120))
        metadata[CladironHealthBackup.ownerSetsKey] = String(decoding: data, as: UTF8.self)
        metadata[CladironHealthBackup.titleKey] = "Restored"
        let object = try HealthBackupDecoder.workout(HealthWorkoutReadPayload(
            healthObjectID: UUID(), kind: .strength, activityType: .traditionalStrength,
            start: start, end: start.addingTimeInterval(180), metadata: metadata, source: .iphone))
        let plan = HealthRestorePlan(operations: [HealthRestoreOperation(object: object, action: .replace)])

        let report = try WorkoutRepository.applyHealthRestore(plan, in: ctx)
        #expect(report.replaced == 1)
        #expect(session.orderedSets.filter { $0.isOwnerSet }.map(\.weight) == [57])
        #expect(session.orderedSets.filter { !$0.isOwnerSet }.map(\.weight) == [30])
        #expect(session.title == "Restored")
    }

    // Feedback batch 6 item 3 — a manually logged cardio workout lands in history
    // identically to a recorded one, but flagged isLogged with its custom title.
    @Test func saveLoggedCardioFlagsAndTitles() throws {
        let ctx = try makeContext()
        let start = Date(timeIntervalSince1970: 1000)
        let c = try WorkoutRepository.saveLoggedCardio(
            type: .other, start: start, durationSeconds: 1500,
            distanceMeters: 2000, customTitle: "  Rowing  ", in: ctx)
        #expect(c.isLogged)
        #expect(c.customTitle == "Rowing")          // trimmed
        #expect(c.displayTitle == "Rowing")
        #expect(c.duration == 1500)
        #expect(c.distance == 2000)
        #expect(try WorkoutRepository.allCardio(ctx).count == 1)
    }

    // A blank custom title falls back to the type's display name.
    @Test func saveLoggedCardioBlankTitleFallsBack() throws {
        let ctx = try makeContext()
        let c = try WorkoutRepository.saveLoggedCardio(
            type: .run, start: Date(timeIntervalSince1970: 0),
            durationSeconds: 600, customTitle: "   ", in: ctx)
        #expect(c.customTitle == nil)
        #expect(c.displayTitle == "Run")
        #expect(c.isLogged)
    }

    // Manual strength logging (feedback batch 7 follow-up) — a logged strength
    // session flags isLogged, keeps its back-dated date, and surfaces in unified
    // history identically to a live one; logging from a preset pre-loads its
    // movements and flags isLogged too.
    @Test func createLoggedStrengthSessionFlagsAndSurfaces() throws {
        let ctx = try makeContext()
        let date = Date(timeIntervalSince1970: 5000)
        let s = try WorkoutRepository.createSession(title: "Workout", date: date,
                                                    isLogged: true, in: ctx)
        #expect(s.isLogged)
        #expect(s.date == date)
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)
        _ = try WorkoutRepository.addSet(to: s, exercise: bench, weightKg: 100, reps: 5,
                                         completedAt: date, in: ctx)
        let history = try WorkoutRepository.unifiedHistory(ctx)
        let logged = history.compactMap { if case let .strength(ws) = $0 { return ws } else { return nil } }
        #expect(logged.contains { $0.id == s.id && $0.isLogged })
    }

    @Test func startLoggedPlanSessionPreloadsMovements() throws {
        let ctx = try makeContext()
        let preset = try #require(PlanCatalog.plan(forKey: "preset-5x5-1a"))
        let s = try WorkoutRepository.startSession(from: preset,
                                                   date: Date(timeIntervalSince1970: 100),
                                                   isLogged: true, in: ctx)
        #expect(s.isLogged)
        #expect(s.planKey == "preset-5x5-1a")
        #expect(s.plannedExerciseNames.contains("Back Squat"))
        #expect(s.title.localizedCaseInsensitiveContains("5×5"))
    }

    @Test func startSessionFromUnifiedPlanMaterializesRuntimePrescription() throws {
        let ctx = try makeContext()
        let itemID = UUID()
        let setID = UUID()
        let planSession = Session(
            id: UUID(), title: "Core day",
            items: [.strength(StrengthItem(
                id: itemID, exerciseKey: ExerciseKey(raw: "incline_crunch"), order: 0,
                sets: [PrescribedSet(id: setID, setIndex: 0, repTarget: .exact(12),
                                     load: .bodyweight)]))])

        let workout = try WorkoutRepository.startSession(
            from: planSession,
            athlete: AthleteExecutionSnapshot(),
            exerciseNameByKey: ["incline_crunch": "Incline Crunch"],
            date: Date(timeIntervalSince1970: 500),
            in: ctx)

        #expect(workout.title == "Core day")
        #expect(workout.date == Date(timeIntervalSince1970: 500))
        #expect(workout.planSessionID == planSession.id)
        #expect(workout.plannedExerciseNames == ["Incline Crunch"])
        #expect(workout.plannedPrescriptions.first?.sourceItemID == itemID)
        #expect(workout.plannedPrescriptions.first?.sets.first?.sourceSetID == setID)
        #expect(try WorkoutRepository.allExercises(ctx).contains { $0.name == "Incline Crunch" })
    }

    // Batch 8 — rank past workouts by how many missing body parts they cover.
    @Test func workoutsByMissingCoverageRanksByCoveredCount() throws {
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
            try WorkoutRepository.allSessions(ctx), missing: [.lats, .calves, .chest])
        #expect(ranked.first?.session.id == a.id, "the session covering the most missing parts ranks first")
        #expect(Set(ranked.first?.covered ?? []) == Set([.lats, .calves]))
        #expect(!ranked.contains { $0.session.id == b.id }, "a session covering no missing part is excluded")
    }

    // Batch 8 — a distance goal persists through saveRecordedCardio.
    @Test func recordedCardioCarriesDistanceGoal() throws {
        let ctx = try makeContext()
        let summary = CardioWorkoutSummary(
            id: UUID(), type: .run, start: Date(timeIntervalSince1970: 0),
            end: Date(timeIntervalSince1970: 1800), distanceMeters: 5200,
            targetDistanceMeters: 5000)
        let c = try WorkoutRepository.saveRecordedCardio(summary, source: .iphone,
                                                         healthKitWorkoutUUID: nil, in: ctx)
        #expect(c.targetDistance == 5000)
        let progress = CardioMath.goalProgress(distanceMeters: c.distance ?? 0, goalMeters: c.targetDistance)
        #expect(progress?.fraction == 1, "5.2 km of a 5 km goal is complete (clamped)")
        #expect(progress?.remainingMeters == 0)
    }

    @Test func goalProgressNilWhenNoGoal() {
        #expect(CardioMath.goalProgress(distanceMeters: 1000, goalMeters: nil) == nil)
        let p = CardioMath.goalProgress(distanceMeters: 2500, goalMeters: 5000)
        #expect(abs((p?.fraction ?? 0) - 0.5) <= 0.001)
        #expect(abs((p?.remainingMeters ?? 0) - 2500) <= 0.001)
    }

    @Test func recentPRs() throws {
        let ctx = try makeContext()
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)
        let squat = try WorkoutRepository.findOrCreateExercise(named: "Squat", in: ctx)
        let s = try WorkoutRepository.createSession(date: Date(timeIntervalSince1970: 1000), in: ctx)
        _ = try WorkoutRepository.addSet(to: s, exercise: bench, weightKg: 100, reps: 5,
                                         completedAt: Date(timeIntervalSince1970: 1000), in: ctx)
        _ = try WorkoutRepository.addSet(to: s, exercise: squat, weightKg: 140, reps: 5,
                                         completedAt: Date(timeIntervalSince1970: 2000), in: ctx)
        let prs = try WorkoutRepository.recentPRs(ctx, rule: .topWeight, formula: .epley)
        #expect(prs.count == 2)
        #expect(prs.first?.exerciseName == "Squat") // most recent first
    }

    @Test func trendSeriesBestPerDay() throws {
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
        #expect(series.count == 2)        // two days
        #expect(series[0].value == 110)   // best of day 1
        #expect(series[1].value == 105)
    }

    @Test func pRTimelineProgressiveOnly() throws {
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
        #expect(timeline.map(\.value) == [100, 110])
    }

    @Test func trainingDays() throws {
        let ctx = try makeContext()
        _ = try WorkoutRepository.createSession(date: Date(timeIntervalSince1970: 0), in: ctx)
        _ = try WorkoutRepository.createSession(date: Date(timeIntervalSince1970: 3600), in: ctx) // same day
        _ = try WorkoutRepository.createSession(date: Date(timeIntervalSince1970: 200_000), in: ctx)
        let days = try WorkoutRepository.trainingDays(ctx, calendar: {
            var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
        }())
        #expect(days.count == 2)
    }

    @Test func exportImportRoundTrip() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(title: "Push", in: ctx)
        let ex = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", category: .push, in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: ex, weightKg: 100, reps: 5, rpe: 8, in: ctx)

        let export = try WorkoutRepository.buildExport(ctx)
        #expect(export.sessions.count == 1)
        #expect(export.sessions[0].sets.count == 1)

        // merge into a fresh store
        let ctx2 = try makeContext()
        let added = try WorkoutRepository.merge(export, in: ctx2)
        #expect(added == 1)
        let sessions = try WorkoutRepository.allSessions(ctx2)
        #expect(sessions.count == 1)
        #expect(sessions[0].orderedSets.first?.weight == 100)
        // merging again is a no-op (dedup by id)
        #expect(try WorkoutRepository.merge(export, in: ctx2) == 0)
    }

    @Test func applyParsedSessions() throws {
        let ctx = try makeContext()
        let parsed = GmailImporter.parse("# Push 2024-01-15\nBench Press 100 3x5").sessions
        let count = try WorkoutRepository.apply(parsed, in: ctx)
        #expect(count == 1)
        let sessions = try WorkoutRepository.allSessions(ctx)
        #expect(sessions.count == 1)
        #expect(sessions[0].orderedSets.count == 3)
        #expect(sessions[0].title == "Push")
    }

    @Test func reassignAndDeleteExercise() throws {
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
        #expect(moved == 2)
        let sessions = try WorkoutRepository.allSessions(ctx)
        #expect(sessions.count == 1)
        for set in sessions[0].orderedSets {
            #expect(set.exercise?.name == "Torso Rotation")
        }
        let remaining = try WorkoutRepository.allExercises(ctx)
        #expect(remaining.first { $0.name == "rotary torso" } == nil)
    }

    // MARK: - Per-performer prescriptions (field test 2026-08-18 #4, decision D11)

    @Test func plannedPerformerPrescriptionsEncodeAndDecode() throws {
        let ctx = try makeContext()
        let session = WorkoutSession(title: "Push", date: Date()); ctx.insert(session)
        let partnerID = UUID()
        session.plannedPerformerPrescriptions = [
            PlannedPerformerPrescription(performerID: nil, exercises: [
                PlannedExercisePrescription(exerciseName: "Bench Press",
                                            sets: [PlannedSetPrescription(targetReps: 8, targetWeightKg: 100)])]),
            PlannedPerformerPrescription(performerID: partnerID.uuidString, exercises: [
                PlannedExercisePrescription(exerciseName: "Bench Press",
                                            sets: [PlannedSetPrescription(targetReps: 12, targetWeightKg: 60)])])
        ]
        try ctx.save()

        let stored = session.plannedPerformerPrescriptions
        #expect(stored.count == 2)
        #expect(stored[1].exercises.first?.sets.first?.targetWeightKg == 60)
        #expect(session.plannedPrescriptions(forPerformerID: partnerID).first?.sets.first?.targetReps == 12)
    }

    @Test func plannedPrescriptionsForPerformerFallsBackToTheOwnerPlan() throws {
        let ctx = try makeContext()
        let session = WorkoutSession(title: "Push", date: Date()); ctx.insert(session)
        session.plannedPrescriptions = [PlannedExercisePrescription(
            exerciseName: "Bench Press",
            sets: [PlannedSetPrescription(targetReps: 5, targetWeightKg: 100)])]
        session.plannedPerformerPrescriptions = [
            PlannedPerformerPrescription(performerID: nil, exercises: session.plannedPrescriptions)]

        let unknown = UUID()
        #expect(session.plannedPrescriptions(forPerformerID: unknown).first?.sets.first?.targetReps == 5,
                       "A performer with no stored plan trains on the owner's prescription")
    }

    @Test func emptyPerformerDataDecodesToEmptyArray() throws {
        let ctx = try makeContext()
        let session = WorkoutSession(title: "Push", date: Date()); ctx.insert(session)

        #expect(session.plannedPerformerPrescriptions.isEmpty)
        session.plannedPerformerPrescriptions = []
        #expect(session.plannedPerformerPrescriptions.isEmpty,
                      "Storing an empty roster must not leave undecodable data behind")
    }

    @Test func sessionsAndCardioSinceAreDateBoundedAndExcludeDeleted() throws {
        let ctx = try makeContext()
        let weekStart = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let before = try WorkoutRepository.createSession(title: "old", date: weekStart.addingTimeInterval(-86_400), in: ctx)
        let boundary = try WorkoutRepository.createSession(title: "b", date: weekStart, in: ctx)
        let after = try WorkoutRepository.createSession(title: "n", date: weekStart.addingTimeInterval(86_400), in: ctx)
        let deleted = try WorkoutRepository.createSession(title: "d", date: weekStart.addingTimeInterval(1), in: ctx)
        try WorkoutRepository.softDeleteSession(deleted, in: ctx)
        let ids = Set(try WorkoutRepository.sessions(since: weekStart, in: ctx).map(\.id))
        #expect(ids == Set([boundary.id, after.id]))
        #expect(!ids.contains(before.id))

        let cOld = try WorkoutRepository.saveLoggedCardio(type: .run, start: weekStart.addingTimeInterval(-60), durationSeconds: 600, in: ctx)
        let cNew = try WorkoutRepository.saveLoggedCardio(type: .run, start: weekStart, durationSeconds: 600, in: ctx)
        let cDel = try WorkoutRepository.saveLoggedCardio(type: .run, start: weekStart.addingTimeInterval(10), durationSeconds: 600, in: ctx)
        try WorkoutRepository.softDeleteCardio(cDel, in: ctx)
        let cids = Set(try WorkoutRepository.cardio(since: weekStart, in: ctx).map(\.id))
        #expect(cids == Set([cNew.id]))
        #expect(!cids.contains(cOld.id))
    }
}
#endif
