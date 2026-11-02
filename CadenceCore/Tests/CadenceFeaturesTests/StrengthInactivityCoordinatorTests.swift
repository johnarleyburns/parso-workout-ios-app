import XCTest
import SwiftData
import CadenceCore
import CadenceFeatures

@MainActor
final class StrengthInactivityCoordinatorTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func make() throws -> (ActiveWorkoutModel, WorkoutSession, ModelContext) {
        let container = try CadenceStore.makeModelContainer(inMemory: true)
        let ctx = ModelContext(container)
        let session = WorkoutSession(title: "Push", date: t0)
        ctx.insert(session)
        let m = ActiveWorkoutModel(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        m.startStrength(session, now: t0)
        return (m, session, ctx)
    }

    func testStartInitializesActivityAndExpiryEndsAtDeadline() throws {
        let (m, s, _) = try make()
        XCTAssertEqual(s.lastMeaningfulActivityAt, t0)
        XCTAssertNil(m.reconcileStrengthInactivity(enabled: true, timeoutMinutes: 10, now: t0.addingTimeInterval(599)))
        let late = t0.addingTimeInterval(11 * 3600)
        XCTAssertEqual(m.reconcileStrengthInactivity(enabled: true, timeoutMinutes: 10, now: late), .finalized)
        XCTAssertEqual(s.endedAt, t0.addingTimeInterval(600))
        XCTAssertEqual(s.inactivityAutoEndedAt, late)
        XCTAssertEqual(s.endReasonRaw, "inactivity")
        XCTAssertFalse(m.isActive)
        XCTAssertNotNil(m.inactivityNotice)
        XCTAssertNil(m.presentedSurface)
    }

    func testExactBoundaryEndsAndRepeatIsNoOpWithOneFinalizerCall() throws {
        let (m, s, _) = try make()
        var calls = 0
        m.strengthFinalizer = { _, _ in calls += 1 }
        let now = t0.addingTimeInterval(600)
        XCTAssertEqual(m.reconcileStrengthInactivity(enabled: true, timeoutMinutes: 10, now: now), .finalized)
        XCTAssertNil(m.reconcileStrengthInactivity(enabled: true, timeoutMinutes: 10, now: now.addingTimeInterval(5)))
        XCTAssertEqual(m.finalizeStrength(sessionID: s.id, endedAt: now, reason: .user), .alreadyEnded)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(s.endReasonRaw, "inactivity")
    }

    func testMeaningfulActivityExtendsDeadlineButPassiveDoesNot() throws {
        let (m, s, _) = try make()
        m.recordMeaningfulActivity(.setMutation, now: t0.addingTimeInterval(599))
        XCTAssertNil(m.reconcileStrengthInactivity(enabled: true, timeoutMinutes: 10, now: t0.addingTimeInterval(700)))
        // Passive lifecycle work never touches the baseline.
        m.writeHeartbeat(now: t0.addingTimeInterval(800))
        m.recordActivityAutoResume(now: t0.addingTimeInterval(800))
        XCTAssertEqual(s.lastMeaningfulActivityAt, t0.addingTimeInterval(599))
        XCTAssertEqual(m.reconcileStrengthInactivity(enabled: true, timeoutMinutes: 10, now: t0.addingTimeInterval(1199)), .finalized)
        XCTAssertEqual(s.endedAt, t0.addingTimeInterval(1199))
    }

    func testDisabledOrLegacyMetadataNeverEnds() throws {
        let (m, s, _) = try make()
        XCTAssertNil(m.reconcileStrengthInactivity(enabled: false, timeoutMinutes: 10, now: t0.addingTimeInterval(86_400)))
        XCTAssertTrue(m.isActive)
        s.lastMeaningfulActivityAt = nil
        XCTAssertNil(m.reconcileStrengthInactivity(enabled: true, timeoutMinutes: 10, now: t0.addingTimeInterval(86_400)))
        XCTAssertTrue(m.isActive)
    }

    func testRelaunchAdoptedSessionReconcilesToOriginalDeadlineAndKeepsSets() throws {
        let container = try CadenceStore.makeModelContainer(inMemory: true)
        let ctx = ModelContext(container)
        let s = WorkoutSession(title: "Legs", date: t0)
        s.lastMeaningfulActivityAt = t0.addingTimeInterval(120)
        ctx.insert(s)
        ctx.insert(SetEntry(weight: 100, reps: 5, order: 0, completedAt: t0, session: s))
        let m = ActiveWorkoutModel(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        m.adopt(s, heartbeat: nil, now: t0.addingTimeInterval(7200))
        XCTAssertEqual(s.lastMeaningfulActivityAt, t0.addingTimeInterval(120), "adoption is not activity")
        XCTAssertEqual(m.reconcileStrengthInactivity(enabled: true, timeoutMinutes: 10, now: t0.addingTimeInterval(7200)), .finalized)
        XCTAssertEqual(s.endedAt, t0.addingTimeInterval(720))
        XCTAssertEqual(s.orderedSets.count, 1)
    }

    func testNewFieldsRoundTripThroughExportAndLegacyDecodesNil() throws {
        let (m, s, ctx) = try make()
        m.reconcileStrengthInactivity(enabled: true, timeoutMinutes: 10, now: t0.addingTimeInterval(900))
        try ctx.save()
        let export = try WorkoutRepository.buildExport(ctx)
        let row = try XCTUnwrap(export.sessions.first { $0.id == s.id })
        XCTAssertEqual(row.endReasonRaw, "inactivity")
        XCTAssertEqual(row.lastMeaningfulActivityAt, t0)
        let legacy = ExportSession(id: UUID(), title: "Old", date: t0, notes: nil, sets: [])
        let data = try JSONEncoder().encode(legacy)
        let back = try JSONDecoder().decode(ExportSession.self, from: data)
        XCTAssertNil(back.lastMeaningfulActivityAt)
        XCTAssertNil(back.endReasonRaw)
    }
}
