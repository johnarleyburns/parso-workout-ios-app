import XCTest
import SwiftData
import CadenceCore
import CadenceFeatures

/// Launch-blockers Phase 1e: crash/upgrade recovery. A workout is NEVER lost —
/// the candidate is adopted paused with the dead gap excluded from elapsed,
/// and never auto-presented or discarded, no matter how stale.
@MainActor
final class ActiveSessionRecoveryTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let container = try CadenceStore.makeModelContainer(inMemory: true)
        return ModelContext(container)
    }

    private func testDefaults() -> UserDefaults {
        let d = UserDefaults(suiteName: "recovery-tests-\(UUID().uuidString)")!
        d.removePersistentDomain(forName: "recovery-tests")
        return d
    }

    func testPicksMostRecentUnfinished() throws {
        let ctx = try makeContext()
        let older = WorkoutSession(title: "A", date: Date(timeIntervalSince1970: 1_000))
        let newer = WorkoutSession(title: "B", date: Date(timeIntervalSince1970: 2_000))
        ctx.insert(older); ctx.insert(newer)
        XCTAssertEqual(ActiveSessionRecovery.candidate(in: [older, newer])?.id, newer.id)
    }

    func testIgnoresEndedDeletedAndLogged() throws {
        let ctx = try makeContext()
        let ended = WorkoutSession(title: "Ended", date: Date())
        ended.endedAt = Date()
        let deleted = WorkoutSession(title: "Deleted", date: Date())
        deleted.deletedAt = Date()
        let logged = WorkoutSession(title: "Logged", date: Date(), isLogged: true)
        ctx.insert(ended); ctx.insert(deleted); ctx.insert(logged)
        XCTAssertNil(ActiveSessionRecovery.candidate(in: [ended, deleted, logged]))
    }

    func testAdoptFoldsDeadGapAsPausedSpan() throws {
        let ctx = try makeContext()
        let start = Date(timeIntervalSince1970: 1_000_000)
        let session = WorkoutSession(title: "Crash", date: start)
        ctx.insert(session)

        // Trained 10 min, heartbeat written, then the app died for 1 h.
        let lastAlive = start.addingTimeInterval(600)
        let heartbeat = WorkoutHeartbeat(sessionID: session.id, lastAlive: lastAlive,
                                         elapsed: 600, isPaused: false)
        let now = lastAlive.addingTimeInterval(3600)

        let m = ActiveWorkoutModel(defaults: testDefaults())
        m.adopt(session, heartbeat: heartbeat, now: now)

        // Elapsed excludes [lastAlive, now]: still exactly 10 min.
        XCTAssertEqual(m.clock.elapsed(now: now), 600, accuracy: 0.001)
        // And the gap stays excluded while paused.
        XCTAssertEqual(m.clock.elapsed(now: now.addingTimeInterval(300)), 600, accuracy: 0.001)
        // Resuming grows elapsed again from 10 min.
        m.resume(now: now.addingTimeInterval(300))
        XCTAssertEqual(m.clock.elapsed(now: now.addingTimeInterval(360)), 660, accuracy: 0.001)
    }

    func testAdoptStartsPausedNotPresented() throws {
        let ctx = try makeContext()
        let session = WorkoutSession(title: "Crash", date: Date().addingTimeInterval(-120))
        ctx.insert(session)
        let m = ActiveWorkoutModel(defaults: testDefaults())
        m.adopt(session, heartbeat: nil, now: Date())
        XCTAssertTrue(m.isActive)
        XCTAssertTrue(m.isPaused)
        XCTAssertEqual(m.pauseOrigin, .auto)
        XCTAssertNil(m.presentedSurface, "recovery must NOT auto-present the workout screen")
    }

    func testStaleSessionStillRecoverable() throws {
        let ctx = try makeContext()
        let weekOld = WorkoutSession(title: "Stale", date: Date().addingTimeInterval(-7 * 86_400))
        ctx.insert(weekOld)
        XCTAssertEqual(ActiveSessionRecovery.candidate(in: [weekOld])?.id, weekOld.id,
                       "a stale candidate is adopted, never discarded")
        let m = ActiveWorkoutModel(defaults: testDefaults())
        m.adopt(weekOld, heartbeat: nil, now: Date())
        XCTAssertTrue(m.isActive)
        // Without a matching heartbeat nothing is credited — the week-long gap
        // never counts as training time.
        XCTAssertEqual(m.clock.elapsed(now: Date()), 0, accuracy: 1)
    }

    func testMismatchedHeartbeatCreditsNothing() throws {
        let ctx = try makeContext()
        let session = WorkoutSession(title: "Mismatch", date: Date().addingTimeInterval(-1200))
        ctx.insert(session)
        let other = WorkoutHeartbeat(sessionID: UUID(), lastAlive: Date(), elapsed: 900, isPaused: false)
        XCTAssertEqual(ActiveSessionRecovery.adoptedElapsed(sessionID: session.id, heartbeat: other), 0)
        XCTAssertEqual(ActiveSessionRecovery.adoptedElapsed(sessionID: session.id, heartbeat: nil), 0)
    }
}
