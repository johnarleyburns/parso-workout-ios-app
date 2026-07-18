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

    // MARK: Launch-blockers Phase 1b — root cover surface

    private func testDefaults() -> UserDefaults {
        UserDefaults(suiteName: "awm-tests-\(UUID().uuidString)")!
    }

    func testStartPresentsCover() throws {
        let ctx = try makeContext()
        let session = WorkoutSession(title: "Push", date: Date())
        ctx.insert(session)
        let m = ActiveWorkoutModel(defaults: testDefaults())
        m.startStrength(session)
        guard case .session(let s)? = m.presentedSurface else {
            return XCTFail("starting a workout must present the session cover")
        }
        XCTAssertEqual(s.id, session.id)
    }

    func testMinimizeKeepsSessionActive() throws {
        let ctx = try makeContext()
        let session = WorkoutSession(title: "Push", date: Date())
        ctx.insert(session)
        let m = ActiveWorkoutModel(defaults: testDefaults())
        m.startStrength(session)
        m.minimize()
        XCTAssertNil(m.presentedSurface)
        XCTAssertTrue(m.isActive, "minimize is the only way to Home mid-workout — nothing ends")
        m.present()
        guard case .session? = m.presentedSurface else {
            return XCTFail("present() re-opens the cover for the active session")
        }
    }

    func testEndFlipsSurfaceToSummary() throws {
        let ctx = try makeContext()
        let session = WorkoutSession(title: "Push", date: Date())
        ctx.insert(session)
        let m = ActiveWorkoutModel(defaults: testDefaults())
        m.startStrength(session)
        m.endStrength()
        // endStrength leaves the surface up; the summary swap happens when the
        // caller publishes the finished summary (no Home flash between).
        guard case .session? = m.presentedSurface else {
            return XCTFail("surface must survive endStrength until the summary lands")
        }
        m.finishedSummary = FinishedSummary(data: .from(session: session))
        guard case .summary? = m.presentedSurface else {
            return XCTFail("setting finishedSummary must flip the surface to .summary")
        }
    }

    func testSummaryDismissClearsSurface() throws {
        let ctx = try makeContext()
        let session = WorkoutSession(title: "Push", date: Date())
        ctx.insert(session)
        let m = ActiveWorkoutModel(defaults: testDefaults())
        m.startStrength(session)
        m.endStrength()
        m.finishedSummary = FinishedSummary(data: .from(session: session))
        m.finishedSummary = nil
        XCTAssertNil(m.presentedSurface)
    }

    func testPauseOriginDistinguishesAutoFromManual() throws {
        let ctx = try makeContext()
        let session = WorkoutSession(title: "Push", date: Date())
        ctx.insert(session)
        let m = ActiveWorkoutModel(defaults: testDefaults())
        m.startStrength(session)

        // A manual pause is NOT resumed by activity.
        m.pause(origin: .manual)
        XCTAssertEqual(m.pauseOrigin, .manual)
        m.recordActivityAutoResume()
        XCTAssertTrue(m.isPaused, "a manual pause stays until the user resumes")

        m.resume()
        XCTAssertNil(m.pauseOrigin)

        // An auto pause resumes on the next user activity.
        m.pause(origin: .auto)
        XCTAssertEqual(m.pauseOrigin, .auto)
        m.recordActivityAutoResume()
        XCTAssertFalse(m.isPaused)
        XCTAssertNil(m.pauseOrigin)
    }

    func testDiscardActiveClearsEverythingWithoutStampingEnd() throws {
        let ctx = try makeContext()
        let session = WorkoutSession(title: "Push", date: Date())
        ctx.insert(session)
        let m = ActiveWorkoutModel(defaults: testDefaults())
        m.startStrength(session)
        m.discardActive()
        XCTAssertFalse(m.isActive)
        XCTAssertNil(m.presentedSurface)
        XCTAssertNil(session.endedAt)
    }
}
