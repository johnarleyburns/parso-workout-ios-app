import XCTest
import SwiftData
import CadenceCore
import CadenceFeatures

@MainActor
final class ActiveWorkoutModelTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let container = try CadenceStore.makeModelContainer(inMemory: true)
        return ModelContext(container)
    }

    func testStartMakesActiveAndClockTracksSessionStart() throws {
        let ctx = try makeContext()
        let session = WorkoutSession(title: "Push", date: Date(timeIntervalSince1970: 1_000_000))
        ctx.insert(session)
        let m = ActiveWorkoutModel()
        XCTAssertFalse(m.isActive)
        m.startStrength(session)
        XCTAssertTrue(m.isActive)
        XCTAssertEqual(m.clock.startedAt, session.date)
    }

    func testEndStrengthStampsEndedAtAndClears() throws {
        let ctx = try makeContext()
        let session = WorkoutSession(title: "Push", date: Date())
        ctx.insert(session)
        let m = ActiveWorkoutModel()
        m.startStrength(session)
        m.endStrength()
        XCTAssertFalse(m.isActive)
        XCTAssertNotNil(session.endedAt)
        XCTAssertNil(m.strengthSession)
    }

    func testPauseResumeReflectInClock() throws {
        let ctx = try makeContext()
        let session = WorkoutSession(title: "Push", date: Date())
        ctx.insert(session)
        let m = ActiveWorkoutModel()
        m.startStrength(session)
        XCTAssertFalse(m.isPaused)
        m.pause()
        XCTAssertTrue(m.isPaused)
        m.resume()
        XCTAssertFalse(m.isPaused)
    }

    func testEndWithNoActiveSessionIsNoop() {
        let m = ActiveWorkoutModel()
        m.endStrength()
        XCTAssertFalse(m.isActive)
    }
}
