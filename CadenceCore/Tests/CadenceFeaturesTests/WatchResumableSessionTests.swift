#if canImport(SwiftData)
import Testing
import SwiftData
import CadenceCore
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

/// Deleting an abandoned watch-only workout from the Resume row, without
/// opening it (which would start an `HKWorkoutSession` just to throw one away).
@MainActor
struct WatchResumableSessionTests {

    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    @Test func discardingASessionWithSetsTellsThePhoneToDropIt() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(title: "Upper Body", in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 60, reps: 8, in: ctx)
        let id = session.id.uuidString

        let payload = WatchResumableSession.discard(session, in: ctx)

        #expect(payload?["action"] == "discard_session")
        #expect(payload?["session_id"] == id)
        #expect(try WorkoutRepository.allSessions(ctx).isEmpty,
                      "The abandoned session should be gone from the watch's own store")
    }

    @Test func discardingAnEmptySessionSendsNothingToThePhone() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(title: "Upper Body", in: ctx)

        let payload = WatchResumableSession.discard(session, in: ctx)

        #expect(payload == nil, "A session with no sets was never synced, so the phone has nothing to forget")
        #expect(try WorkoutRepository.allSessions(ctx).isEmpty)
    }

    @Test func discardingLeavesOtherSessionsAlone() throws {
        let ctx = try makeContext()
        let keep = try WorkoutRepository.createSession(title: "Keep", in: ctx)
        let drop = try WorkoutRepository.createSession(title: "Drop", in: ctx)

        WatchResumableSession.discard(drop, in: ctx)

        let remaining = try WorkoutRepository.allSessions(ctx)
        #expect(remaining.map(\.id) == [keep.id])
    }
}
#endif
