#if canImport(SwiftData)
import Foundation
import Testing
import SwiftData
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures
import CadencePhoneFeatures

/// Launch-blockers Phase 1e: the UserDefaults-backed liveness heartbeat.
@MainActor
struct WorkoutHeartbeatTests {

    private func testDefaults() -> UserDefaults {
        UserDefaults(suiteName: "heartbeat-tests-\(UUID().uuidString)")!
    }

    @Test func writeReadRoundTrip() {
        let defaults = testDefaults()
        let hb = WorkoutHeartbeat(sessionID: UUID(),
                                  lastAlive: Date(timeIntervalSince1970: 12_345),
                                  elapsed: 678.9,
                                  isPaused: true)
        WorkoutHeartbeatStore.write(hb, defaults: defaults)
        #expect(WorkoutHeartbeatStore.read(defaults: defaults) == hb)
    }

    @Test func clearedOnEnd() throws {
        let container = try CadenceStore.makeModelContainer(inMemory: true)
        let ctx = ModelContext(container)
        let session = WorkoutSession(title: "Push", date: Date())
        ctx.insert(session)
        let defaults = testDefaults()
        let m = ActiveWorkoutModel(defaults: defaults)
        m.startStrength(session)
        m.writeHeartbeat()
        #expect(WorkoutHeartbeatStore.read(defaults: defaults) != nil)
        m.endStrength()
        #expect(WorkoutHeartbeatStore.read(defaults: defaults) == nil)
    }

    @Test func clearedOnDiscard() throws {
        let container = try CadenceStore.makeModelContainer(inMemory: true)
        let ctx = ModelContext(container)
        let session = WorkoutSession(title: "Push", date: Date())
        ctx.insert(session)
        let defaults = testDefaults()
        let m = ActiveWorkoutModel(defaults: defaults)
        m.startStrength(session)
        m.writeHeartbeat()
        m.discardActive()
        #expect(WorkoutHeartbeatStore.read(defaults: defaults) == nil)
    }

    @Test func writeCapturesClockElapsedAndSessionID() throws {
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
        #expect(hb?.sessionID == session.id)
        #expect(hb?.lastAlive == now)
        #expect(abs((hb?.elapsed ?? -1) - 300) <= 0.001)
        #expect(hb?.isPaused == false)
    }

    @Test func mismatchedSessionIgnoredOnAdoption() {
        let hb = WorkoutHeartbeat(sessionID: UUID(), lastAlive: Date(), elapsed: 500, isPaused: false)
        #expect(ActiveSessionRecovery.adoptedElapsed(sessionID: UUID(), heartbeat: hb) == 0)
    }
}
#endif
