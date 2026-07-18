import XCTest
import SwiftData
import CadenceCore
import CadenceFeatures

/// Launch-blockers Phase 1e: the UserDefaults-backed liveness heartbeat.
@MainActor
final class WorkoutHeartbeatTests: XCTestCase {

    private func testDefaults() -> UserDefaults {
        UserDefaults(suiteName: "heartbeat-tests-\(UUID().uuidString)")!
    }

    func testWriteReadRoundTrip() {
        let defaults = testDefaults()
        let hb = WorkoutHeartbeat(sessionID: UUID(),
                                  lastAlive: Date(timeIntervalSince1970: 12_345),
                                  elapsed: 678.9,
                                  isPaused: true)
        WorkoutHeartbeatStore.write(hb, defaults: defaults)
        XCTAssertEqual(WorkoutHeartbeatStore.read(defaults: defaults), hb)
    }

    func testClearedOnEnd() throws {
        let container = try CadenceStore.makeModelContainer(inMemory: true)
        let ctx = ModelContext(container)
        let session = WorkoutSession(title: "Push", date: Date())
        ctx.insert(session)
        let defaults = testDefaults()
        let m = ActiveWorkoutModel(defaults: defaults)
        m.startStrength(session)
        m.writeHeartbeat()
        XCTAssertNotNil(WorkoutHeartbeatStore.read(defaults: defaults))
        m.endStrength()
        XCTAssertNil(WorkoutHeartbeatStore.read(defaults: defaults))
    }

    func testClearedOnDiscard() throws {
        let container = try CadenceStore.makeModelContainer(inMemory: true)
        let ctx = ModelContext(container)
        let session = WorkoutSession(title: "Push", date: Date())
        ctx.insert(session)
        let defaults = testDefaults()
        let m = ActiveWorkoutModel(defaults: defaults)
        m.startStrength(session)
        m.writeHeartbeat()
        m.discardActive()
        XCTAssertNil(WorkoutHeartbeatStore.read(defaults: defaults))
    }

    func testWriteCapturesClockElapsedAndSessionID() throws {
        let container = try CadenceStore.makeModelContainer(inMemory: true)
        let ctx = ModelContext(container)
        let start = Date(timeIntervalSince1970: 1_000_000)
        let session = WorkoutSession(title: "Push", date: start)
        ctx.insert(session)
        let defaults = testDefaults()
        let m = ActiveWorkoutModel(defaults: defaults)
        m.startStrength(session)
        let now = start.addingTimeInterval(300)
        m.writeHeartbeat(now: now)
        let hb = WorkoutHeartbeatStore.read(defaults: defaults)
        XCTAssertEqual(hb?.sessionID, session.id)
        XCTAssertEqual(hb?.lastAlive, now)
        XCTAssertEqual(hb?.elapsed ?? -1, 300, accuracy: 0.001)
        XCTAssertEqual(hb?.isPaused, false)
    }

    func testMismatchedSessionIgnoredOnAdoption() {
        let hb = WorkoutHeartbeat(sessionID: UUID(), lastAlive: Date(), elapsed: 500, isPaused: false)
        XCTAssertEqual(ActiveSessionRecovery.adoptedElapsed(sessionID: UUID(), heartbeat: hb), 0)
    }
}
