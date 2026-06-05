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
                                hrSamples: [HRSamplePoint(t: 0, bpm: 120), HRSamplePoint(t: 60, bpm: 140)])
        XCTAssertEqual(try WorkoutRepository.ingest([w], in: ctx), 1)
        XCTAssertEqual(try WorkoutRepository.ingest([w], in: ctx), 0) // dup skipped
        let all = try WorkoutRepository.allCardio(ctx)
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].orderedHRSamples.count, 2)
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
}
