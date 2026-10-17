import XCTest
import SwiftData
import CadenceCore
@testable import CadenceFeatures

@MainActor
final class WatchLiftSourcesTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    func testMenuOrder() {
        XCTAssertEqual(WatchLiftSources.menuOrder.map(\.title), ["Suggest", "Previous", "Custom"])
        XCTAssertEqual(WatchLiftSources.Source.suggest.accessibilityIdentifier, "watchStrength.suggest")
        XCTAssertEqual(WatchLiftSources.menuTitle, "Lift")
    }

    func testSuggestEmptyForNoSyncCardioAndRest() {
        XCTAssertNil(WatchSuggestReview.make(plan: nil))
        let plan = WatchSync.TodayPlan(sessions: [
            .init(id: "c", kind: .cardio, label: "Run"), .init(id: "r", kind: .rest, label: "Rest")])
        XCTAssertNil(WatchSuggestReview.make(plan: plan))
    }

    func testSuggestPreservesRichPayloadAndStaleness() {
        let payload = WatchPlanPayload(strength: .init(
            exerciseNames: ["Squat", "Row"], repLadder: [5],
            prescriptions: [
                .init(exerciseName: "Squat", sets: [.init(targetReps: 5, restSeconds: 180)]),
                .init(exerciseName: "Row", sets: [.init(targetReps: 10, restSeconds: 90)])]))
        let synced = Date(timeIntervalSince1970: 1_000_000)
        let plan = WatchSync.TodayPlan(sessions: [
            .init(id: "s", kind: .strength, label: "Legs", exerciseNames: ["Squat", "Row"],
                  repLadder: [5], planPayload: payload)], updatedAt: synced)
        let fresh = WatchSuggestReview.make(plan: plan, now: synced)
        XCTAssertEqual(fresh?.isStale, false)
        XCTAssertEqual(fresh?.launch.planPayload, payload)
        XCTAssertEqual(fresh?.launch.title, "Legs")
        XCTAssertEqual(fresh?.launch.exerciseNames, ["Squat", "Row"])
        XCTAssertEqual(fresh?.launch.repLadder, [5])
        let stale = WatchSuggestReview.make(plan: plan, now: synced.addingTimeInterval(3 * 86_400))
        XCTAssertEqual(stale?.isStale, true)
        XCTAssertNotNil(stale?.launch)
    }

    @discardableResult
    private func addSession(_ ctx: ModelContext, title: String, end: Date?, sets: [(String, Int)],
                            deleted: Bool = false, date: Date = Date(timeIntervalSince1970: 100)) throws -> WorkoutSession {
        let s = try WorkoutRepository.createSession(title: title, in: ctx)
        s.date = date
        s.endedAt = end
        if deleted { s.deletedAt = Date() }
        for (name, reps) in sets {
            let ex = try WorkoutRepository.findOrCreateExercise(named: name, in: ctx)
            _ = try WorkoutRepository.addSet(to: s, exercise: ex, weightKg: 50, reps: reps, in: ctx)
        }
        try ctx.save()
        return s
    }

    func testPreviousFiltersAndOrders() throws {
        let ctx = try makeContext()
        for i in 1...6 {
            try addSession(ctx, title: "W\(i)", end: Date(timeIntervalSince1970: Double(1000 + i)),
                           sets: [("Bench Press", 8), ("Bench Press", 8), ("Row", 10)])
        }
        try addSession(ctx, title: "Deleted", end: Date(timeIntervalSince1970: 5000), sets: [("Bench Press", 8)], deleted: true)
        try addSession(ctx, title: "Open", end: nil, sets: [("Bench Press", 8)])
        try addSession(ctx, title: "Empty", end: Date(timeIntervalSince1970: 5000), sets: [])
        try addSession(ctx, title: "ZeroReps", end: Date(timeIntervalSince1970: 5000), sets: [("Bench Press", 0)])
        let list = WatchPreviousWorkout.load(from: ctx)
        XCTAssertEqual(list.map(\.title), ["W6", "W5", "W4", "W3", "W2"])
        XCTAssertEqual(list[0].exerciseCount, 2)
        XCTAssertEqual(list[0].workingSetCount, 3)
        XCTAssertEqual(list[0].structureLines, ["Bench Press · 2×8", "Row · 1×10"])
        XCTAssertEqual(list[0].launch.exerciseNames, ["Bench Press", "Row"])
    }

    func testPreviousEmptyAndFallbackOrdering() throws {
        let ctx = try makeContext()
        XCTAssertTrue(WatchPreviousWorkout.load(from: ctx).isEmpty)
        try addSession(ctx, title: "", end: Date(timeIntervalSince1970: 500), sets: [("Squat", 5)],
                       date: Date(timeIntervalSince1970: 10))
        try addSession(ctx, title: "Later", end: Date(timeIntervalSince1970: 600), sets: [("Squat", 5)],
                       date: Date(timeIntervalSince1970: 5))
        let list = WatchPreviousWorkout.load(from: ctx)
        XCTAssertEqual(list.map(\.title), ["Later", "Strength"])
    }

    func testTemplateStartCreatesNewSessionAndLeavesSourceUntouched() throws {
        let ctx = try makeContext()
        let source = try addSession(ctx, title: "Push", end: Date(timeIntervalSince1970: 900),
                                    sets: [("Bench Press", 8), ("Bench Press", 6)])
        let template = try XCTUnwrap(WatchPreviousWorkout.load(from: ctx).first)
        let sourceSetIDs = source.orderedSets.map(\.id)

        let model = WatchStrengthFlowModel(context: ctx)
        model.start(title: template.launch.title, plannedExerciseNames: template.launch.exerciseNames,
                    repLadder: template.launch.repLadder, planPayload: template.launch.planPayload,
                    createSession: true)
        let created = try XCTUnwrap(model.session)
        XCTAssertNotEqual(created.id, source.id)
        XCTAssertEqual(created.plannedExerciseNames, ["Bench Press"])
        XCTAssertEqual(created.plannedPrescriptions.first?.sets.map(\.targetReps), [8, 6])
        XCTAssertEqual(source.orderedSets.map(\.id), sourceSetIDs)
        XCTAssertEqual(source.endedAt, Date(timeIntervalSince1970: 900))
        XCTAssertTrue(created.orderedSets.isEmpty)
    }
}
