#if canImport(SwiftData)
import Foundation
import Testing
import SwiftData
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures
import CadencePhoneFeatures

@MainActor
struct ActiveWorkoutModelTests {

    private func makeContext() throws -> ModelContext {
        let container = try CadenceStore.makeModelContainer(inMemory: true)
        return ModelContext(container)
    }

    @Test func startMakesActiveAndClockTracksSessionStart() throws {
        let ctx = try makeContext()
        let session = WorkoutSession(title: "Push", date: Date(timeIntervalSince1970: 1_000_000))
        ctx.insert(session)
        let m = ActiveWorkoutModel()
        #expect(!m.isActive)
        m.startStrength(session)
        #expect(m.isActive)
        #expect(m.clock.startedAt == session.date)
    }

    @Test func endStrengthStampsEndedAtAndClears() throws {
        let ctx = try makeContext()
        let session = WorkoutSession(title: "Push", date: Date())
        ctx.insert(session)
        let m = ActiveWorkoutModel()
        m.startStrength(session)
        m.endStrength()
        #expect(!m.isActive)
        #expect(session.endedAt != nil)
        #expect(m.strengthSession == nil)
    }

    @Test func pauseResumeReflectInClock() throws {
        let ctx = try makeContext()
        let session = WorkoutSession(title: "Push", date: Date())
        ctx.insert(session)
        let m = ActiveWorkoutModel()
        m.startStrength(session)
        #expect(!m.isPaused)
        m.pause()
        #expect(m.isPaused)
        m.resume()
        #expect(!m.isPaused)
    }

    @Test func endWithNoActiveSessionIsNoop() {
        let m = ActiveWorkoutModel()
        m.endStrength()
        #expect(!m.isActive)
    }

    // MARK: Launch-blockers Phase 1b — root cover surface

    private func testDefaults() -> UserDefaults {
        UserDefaults(suiteName: "awm-tests-\(UUID().uuidString)")!
    }

    @Test func startPresentsCover() throws {
        let ctx = try makeContext()
        let session = WorkoutSession(title: "Push", date: Date())
        ctx.insert(session)
        let m = ActiveWorkoutModel(defaults: testDefaults())
        m.startStrength(session)
        guard case .session(let s)? = m.presentedSurface else {
            Issue.record("starting a workout must present the session cover")
            return
        }
        #expect(s.id == session.id)
    }

    @Test func minimizeKeepsSessionActive() throws {
        let ctx = try makeContext()
        let session = WorkoutSession(title: "Push", date: Date())
        ctx.insert(session)
        let m = ActiveWorkoutModel(defaults: testDefaults())
        m.startStrength(session)
        m.minimize()
        #expect(m.presentedSurface == nil)
        #expect(m.isActive, "minimize is the only way to Home mid-workout — nothing ends")
        m.present()
        guard case .session? = m.presentedSurface else {
            Issue.record("present() re-opens the cover for the active session")
            return
        }
    }

    @Test func endFlipsSurfaceToSummary() throws {
        let ctx = try makeContext()
        let session = WorkoutSession(title: "Push", date: Date())
        ctx.insert(session)
        let m = ActiveWorkoutModel(defaults: testDefaults())
        m.startStrength(session)
        m.endStrength()
        // endStrength leaves the surface up; the summary swap happens when the
        // caller publishes the finished summary (no Home flash between).
        guard case .session? = m.presentedSurface else {
            Issue.record("surface must survive endStrength until the summary lands")
            return
        }
        m.finishedSummary = FinishedSummary(data: .from(session: session))
        guard case .summary? = m.presentedSurface else {
            Issue.record("setting finishedSummary must flip the surface to .summary")
            return
        }
    }

    @Test func summaryDismissClearsSurface() throws {
        let ctx = try makeContext()
        let session = WorkoutSession(title: "Push", date: Date())
        ctx.insert(session)
        let m = ActiveWorkoutModel(defaults: testDefaults())
        m.startStrength(session)
        m.endStrength()
        m.finishedSummary = FinishedSummary(data: .from(session: session))
        m.finishedSummary = nil
        #expect(m.presentedSurface == nil)
    }

    @Test func pauseOriginDistinguishesAutoFromManual() throws {
        let ctx = try makeContext()
        let session = WorkoutSession(title: "Push", date: Date())
        ctx.insert(session)
        let m = ActiveWorkoutModel(defaults: testDefaults())
        m.startStrength(session)

        // A manual pause is NOT resumed by activity.
        m.pause(origin: .manual)
        #expect(m.pauseOrigin == .manual)
        m.recordActivityAutoResume()
        #expect(m.isPaused, "a manual pause stays until the user resumes")

        m.resume()
        #expect(m.pauseOrigin == nil)

        // An auto pause resumes on the next user activity.
        m.pause(origin: .auto)
        #expect(m.pauseOrigin == .auto)
        m.recordActivityAutoResume()
        #expect(!m.isPaused)
        #expect(m.pauseOrigin == nil)
    }

    @Test func discardActiveClearsEverythingWithoutStampingEnd() throws {
        let ctx = try makeContext()
        let session = WorkoutSession(title: "Push", date: Date())
        ctx.insert(session)
        let m = ActiveWorkoutModel(defaults: testDefaults())
        m.startStrength(session)
        m.discardActive()
        #expect(!m.isActive)
        #expect(m.presentedSurface == nil)
        #expect(session.endedAt == nil)
    }
}
#endif
