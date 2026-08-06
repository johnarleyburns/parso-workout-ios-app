import XCTest
import SwiftData
@testable import CadenceFeatures
import CadenceCore

final class WatchStrengthSyncApplierTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        container = try CadenceStore.makeModelContainer(inMemory: true)
        context = ModelContext(container)
        _ = try WorkoutRepository.seedStarterLibraryIfNeeded(context)
    }

    override func tearDown() {
        context = nil
        container = nil
    }

    func testEndSessionBeforeLogSetCreatesFinalizedNonResumableSession() throws {
        let sessionID = UUID()
        let endedAt = Date(timeIntervalSince1970: 2_000)

        try WatchStrengthSyncApplier.apply(userInfo: [
            "action": "end_session",
            "session_id": sessionID.uuidString,
            "ended_at": endedAt.timeIntervalSince1970,
            "session_title": "Strength",
            "planned_exercises": ["Bench Press"],
            "planned_rep_ladder": [12, 10, 8],
        ], in: context)

        try WatchStrengthSyncApplier.apply(userInfo: [
            "action": "log_set",
            "session_id": sessionID.uuidString,
            "set_id": UUID().uuidString,
            "exercise": "Bench Press",
            "weight": 80.0,
            "reps": 8,
            "rpe": 8.0,
            "session_title": "Strength",
            "planned_exercises": ["Bench Press"],
            "planned_rep_ladder": [12, 10, 8],
        ], in: context)

        let session = try XCTUnwrap(fetchSessions().first { $0.id == sessionID })
        XCTAssertEqual(session.endedAt, endedAt)
        XCTAssertFalse(session.isResumable)
        XCTAssertEqual(session.orderedSets.count, 1)
        XCTAssertEqual(session.orderedSets.first?.rpe, 8)
    }

    func testLogSetStoresIncomingSetIDSoReplayIsIgnored() throws {
        let sessionID = UUID()
        let setID = UUID()
        let payload: [String: Any] = [
            "action": "log_set",
            "session_id": sessionID.uuidString,
            "set_id": setID.uuidString,
            "exercise": "Bench Press",
            "weight": 80.0,
            "reps": 8,
        ]

        let first = try WatchStrengthSyncApplier.apply(userInfo: payload, in: context)
        let second = try WatchStrengthSyncApplier.apply(userInfo: payload, in: context)

        let session = try XCTUnwrap(fetchSessions().first { $0.id == sessionID })
        XCTAssertEqual(first, .logSet)
        XCTAssertEqual(second, .ignored)
        XCTAssertEqual(session.orderedSets.count, 1)
        XCTAssertEqual(session.orderedSets.first?.id, setID)
    }

    func testDeleteSetPayloadRemovesMirroredSet() throws {
        let session = try WorkoutRepository.createSession(title: "Strength", in: context)
        let exercise = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: context)
        let set = try WorkoutRepository.addSet(to: session, exercise: exercise, weightKg: 80, reps: 8, in: context)

        let action = try WatchStrengthSyncApplier.apply(userInfo: [
            "action": "delete_set",
            "session_id": session.id.uuidString,
            "set_id": set.id.uuidString,
        ], in: context)

        XCTAssertEqual(action, .deleteSet)
        XCTAssertTrue(session.orderedSets.isEmpty)
    }

    func testDeleteExercisePayloadRemovesSetsAndPlannedName() throws {
        let session = try WorkoutRepository.createSession(title: "Strength", in: context)
        let exercise = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: context)
        session.plannedExerciseNames = ["Bench Press"]
        _ = try WorkoutRepository.addSet(to: session, exercise: exercise, weightKg: 80, reps: 8, in: context)

        let action = try WatchStrengthSyncApplier.apply(userInfo: [
            "action": "delete_exercise",
            "session_id": session.id.uuidString,
            "exercise": "Bench Press",
        ], in: context)

        XCTAssertEqual(action, .deleteExercise)
        XCTAssertTrue(session.orderedSets.isEmpty)
        XCTAssertTrue(session.plannedExerciseNames.isEmpty)
    }

    private func fetchSessions() throws -> [WorkoutSession] {
        try context.fetch(FetchDescriptor<WorkoutSession>())
    }
}
