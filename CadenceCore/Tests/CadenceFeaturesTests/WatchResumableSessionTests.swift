import XCTest
import SwiftData
import CadenceCore
@testable import CadenceFeatures

/// Deleting an abandoned watch-only workout from the Resume row, without
/// opening it (which would start an `HKWorkoutSession` just to throw one away).
@MainActor
final class WatchResumableSessionTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    func testDiscardingASessionWithSetsTellsThePhoneToDropIt() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(title: "Upper Body", in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 60, reps: 8, in: ctx)
        let id = session.id.uuidString

        let payload = WatchResumableSession.discard(session, in: ctx)

        XCTAssertEqual(payload?["action"], "discard_session")
        XCTAssertEqual(payload?["session_id"], id)
        XCTAssertTrue(try WorkoutRepository.allSessions(ctx).isEmpty,
                      "The abandoned session should be gone from the watch's own store")
    }

    func testDiscardingAnEmptySessionSendsNothingToThePhone() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(title: "Upper Body", in: ctx)

        let payload = WatchResumableSession.discard(session, in: ctx)

        XCTAssertNil(payload, "A session with no sets was never synced, so the phone has nothing to forget")
        XCTAssertTrue(try WorkoutRepository.allSessions(ctx).isEmpty)
    }

    func testDiscardingLeavesOtherSessionsAlone() throws {
        let ctx = try makeContext()
        let keep = try WorkoutRepository.createSession(title: "Keep", in: ctx)
        let drop = try WorkoutRepository.createSession(title: "Drop", in: ctx)

        WatchResumableSession.discard(drop, in: ctx)

        let remaining = try WorkoutRepository.allSessions(ctx)
        XCTAssertEqual(remaining.map(\.id), [keep.id])
    }
}
