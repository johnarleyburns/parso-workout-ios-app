#if canImport(SwiftData)
import Foundation
import Testing
import SwiftData
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures
import CadencePhoneFeatures

@MainActor
struct StrengthInactivityCoordinatorTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func make() throws -> (ActiveWorkoutModel, WorkoutSession, ModelContext) {
        let container = try CadenceStore.makeModelContainer(inMemory: true)
        let ctx = ModelContext(container)
        let session = WorkoutSession(title: "Push", date: t0)
        ctx.insert(session)
        let m = ActiveWorkoutModel(defaults: InMemoryDefaultsStore())
        m.startStrength(session, now: t0)
        return (m, session, ctx)
    }

    @Test func startInitializesActivityAndExpiryEndsAtDeadline() throws {
        let (m, s, _) = try make()
        #expect(s.lastMeaningfulActivityAt == t0)
        #expect(m.reconcileStrengthInactivity(enabled: true, timeoutMinutes: 10, now: t0.addingTimeInterval(599)) == nil)
        let late = t0.addingTimeInterval(11 * 3600)
        #expect(m.reconcileStrengthInactivity(enabled: true, timeoutMinutes: 10, now: late) == .finalized)
        #expect(s.endedAt == t0.addingTimeInterval(600))
        #expect(s.inactivityAutoEndedAt == late)
        #expect(s.endReasonRaw == "inactivity")
        #expect(!m.isActive)
        #expect(m.inactivityNotice != nil)
        #expect(m.presentedSurface == nil)
    }

    @Test func exactBoundaryEndsAndRepeatIsNoOpWithOneFinalizerCall() throws {
        let (m, s, _) = try make()
        var calls = 0
        m.strengthFinalizer = { _, _ in calls += 1 }
        let now = t0.addingTimeInterval(600)
        #expect(m.reconcileStrengthInactivity(enabled: true, timeoutMinutes: 10, now: now) == .finalized)
        #expect(m.reconcileStrengthInactivity(enabled: true, timeoutMinutes: 10, now: now.addingTimeInterval(5)) == nil)
        #expect(m.finalizeStrength(sessionID: s.id, endedAt: now, reason: .user) == .alreadyEnded)
        #expect(calls == 1)
        #expect(s.endReasonRaw == "inactivity")
    }

    @Test func meaningfulActivityExtendsDeadlineButPassiveDoesNot() throws {
        let (m, s, _) = try make()
        m.recordMeaningfulActivity(.setMutation, now: t0.addingTimeInterval(599))
        #expect(m.reconcileStrengthInactivity(enabled: true, timeoutMinutes: 10, now: t0.addingTimeInterval(700)) == nil)
        // Passive lifecycle work never touches the baseline.
        m.writeHeartbeat(now: t0.addingTimeInterval(800))
        m.recordActivityAutoResume(now: t0.addingTimeInterval(800))
        #expect(s.lastMeaningfulActivityAt == t0.addingTimeInterval(599))
        #expect(m.reconcileStrengthInactivity(enabled: true, timeoutMinutes: 10, now: t0.addingTimeInterval(1199)) == .finalized)
        #expect(s.endedAt == t0.addingTimeInterval(1199))
    }

    @Test func disabledOrLegacyMetadataNeverEnds() throws {
        let (m, s, _) = try make()
        #expect(m.reconcileStrengthInactivity(enabled: false, timeoutMinutes: 10, now: t0.addingTimeInterval(86_400)) == nil)
        #expect(m.isActive)
        s.lastMeaningfulActivityAt = nil
        #expect(m.reconcileStrengthInactivity(enabled: true, timeoutMinutes: 10, now: t0.addingTimeInterval(86_400)) == nil)
        #expect(m.isActive)
    }

    @Test func relaunchAdoptedSessionReconcilesToOriginalDeadlineAndKeepsSets() throws {
        let container = try CadenceStore.makeModelContainer(inMemory: true)
        let ctx = ModelContext(container)
        let s = WorkoutSession(title: "Legs", date: t0)
        s.lastMeaningfulActivityAt = t0.addingTimeInterval(120)
        ctx.insert(s)
        ctx.insert(SetEntry(weight: 100, reps: 5, order: 0, completedAt: t0, session: s))
        let m = ActiveWorkoutModel(defaults: InMemoryDefaultsStore())
        m.adopt(s, heartbeat: nil, now: t0.addingTimeInterval(7200))
        #expect(s.lastMeaningfulActivityAt == t0.addingTimeInterval(120), "adoption is not activity")
        #expect(m.reconcileStrengthInactivity(enabled: true, timeoutMinutes: 10, now: t0.addingTimeInterval(7200)) == .finalized)
        #expect(s.endedAt == t0.addingTimeInterval(720))
        #expect(s.orderedSets.count == 1)
    }

    @Test func newFieldsRoundTripThroughExportAndLegacyDecodesNil() throws {
        let (m, s, ctx) = try make()
        m.reconcileStrengthInactivity(enabled: true, timeoutMinutes: 10, now: t0.addingTimeInterval(900))
        try ctx.save()
        let export = try WorkoutRepository.buildExport(ctx)
        let row = try #require(export.sessions.first { $0.id == s.id })
        #expect(row.endReasonRaw == "inactivity")
        #expect(row.lastMeaningfulActivityAt == t0)
        let legacy = ExportSession(id: UUID(), title: "Old", date: t0, notes: nil, sets: [])
        let data = try JSONEncoder().encode(legacy)
        let back = try JSONDecoder().decode(ExportSession.self, from: data)
        #expect(back.lastMeaningfulActivityAt == nil)
        #expect(back.endReasonRaw == nil)
    }
}
#endif
