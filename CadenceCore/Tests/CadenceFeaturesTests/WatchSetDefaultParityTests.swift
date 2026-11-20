#if canImport(SwiftData)
import Foundation
import Testing
import SwiftData
import CadencePhoneFeatures
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures
import CadenceCore

/// Issue #433: phone history → built snapshot → context round trip → persisted → Watch flow
/// chooses the same defaults the phone's `PerformerSetPlanner.resolve` inputs would.
@MainActor
final class WatchSetDefaultParityTests {
    private var phone: ModelContext!
    private var watch: ModelContext!
    private var sam: Person!
    private let base = Date(timeIntervalSince1970: 1_700_000_000)
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        phone = ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
        watch = ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
        _ = try WorkoutRepository.seedStarterLibraryIfNeeded(watch)
        sam = Person(name: "Sam")
        phone.insert(sam)
    }

    private struct Provider: WatchSetDefaultHistoryProviding {
        var snapshot: WatchSetDefaultSnapshot
        func history(exerciseKey: String, performerID: String, performerName: String?) -> PerformerSetPlanner.History {
            snapshot.history(exerciseKey: exerciseKey, performerID: performerID, performerName: performerName)
        }
    }

    private func addSession(day: Int, _ rows: [(String, Double, Int, Person?)]) {
        let s = WorkoutSession(title: "S", date: base.addingTimeInterval(Double(day) * 86_400),
                               endedAt: base.addingTimeInterval(Double(day) * 86_400 + 3_600))
        phone.insert(s)
        var exercises: [String: Exercise] = [:]
        for (i, r) in rows.enumerated() {
            let e = exercises[r.0] ?? Exercise(name: r.0)
            if exercises[r.0] == nil { phone.insert(e); exercises[r.0] = e }
            // A deterministic `completedAt` (not the `Date()` default): the sample
            // timestamp now round-trips through the JSON snapshot payload, and the
            // live wall clock's sub-microsecond component doesn't survive that
            // round trip bit-for-bit on every platform, which made `syncedSnapshot`'s
            // `received == built` assertion flaky under CI even though both sides
            // printed identically at whole-second resolution.
            phone.insert(SetEntry(weight: r.1, reps: r.2, order: i,
                                  completedAt: base.addingTimeInterval(Double(day) * 86_400 + Double(i)),
                                  session: s, exercise: e, performedBy: r.3))
        }
    }

    /// Phone build → context dictionary → Watch apply → persisted → relaunch load.
    private func syncedSnapshot() throws -> WatchSetDefaultSnapshot {
        try phone.save()
        let built = try WatchSetDefaultSnapshotBuilder.make(context: phone, now: now)
        let ctx = WatchSync.IncomingContext.from(
            context: [WatchSync.Key.setDefaultSnapshot: built.propertyList], applyingTo: .init())
        let received = try #require(ctx.setDefaultSnapshot)
        #expect(received == built)
        let defaults = InMemoryDefaultsStore()
        #expect(WatchSetDefaultSnapshotPersistence(defaults: defaults).replaceIfNewer(received) == .replaced)
        // Relaunch: a fresh persistence object, phone unreachable.
        return try #require(WatchSetDefaultSnapshotPersistence(defaults: defaults).load())
    }

    private func flow(_ snapshot: WatchSetDefaultSnapshot, partner: Person? = nil,
                      plan: WatchPlanPayload.Strength? = nil) -> WatchStrengthFlowModel {
        let m = WatchStrengthFlowModel(context: watch, unit: .kilograms, cooldownDefault: 5,
                                       restDefault: 90, setDefaultHistory: Provider(snapshot: snapshot))
        var strength = plan ?? .init(exerciseNames: ["Bench Press"])
        if let partner {
            strength.performers = [.owner(), .init(id: partner.id.uuidString, displayName: partner.name, isOwner: false)]
        }
        m.start(title: "Push", plannedExerciseNames: ["Bench Press"],
                planPayload: WatchPlanPayload(strength: strength), createSession: true)
        if partner != nil { m.selectPerformer(at: 1) }
        return m
    }

    private func direct(_ snap: WatchSetDefaultSnapshot, performer: String, owner: Bool)
        -> PerformerSetPlanner.Resolved {
        PerformerSetPlanner.resolve(
            setIndex: 0, performerPlan: nil, ownerPlan: [], ownerLadder: nil, isOwner: owner,
            history: snap.history(exerciseKey: "Bench Press", performerID: performer))
    }

    @Test func ownerHistoryMatchesPhoneAfterRelaunch() throws {
        addSession(day: 1, [("Bench Press", 80, 8, nil), ("Bench Press", 80, 8, nil)])
        let snap = try syncedSnapshot()
        let m = flow(snap)
        m.startLogSet(for: m.exerciseList[0].exercise)
        let d = direct(snap, performer: "owner", owner: true)
        #expect(m.currentWeight == d.weightKg); #expect(m.currentReps == Double(d.reps))
        #expect(m.currentWeight == 80)
    }

    @Test func watchLoggedSetThenExplicitPlan() throws {
        addSession(day: 1, [("Bench Press", 80, 8, nil)])
        let snap = try syncedSnapshot()
        let m = flow(snap)
        let ex = m.exerciseList[0].exercise
        m.startLogSet(for: ex)
        m.currentWeight = 85; m.currentReps = 5
        _ = m.logSet(); m.finishRest()
        m.startLogSet(for: ex)
        #expect(m.currentWeight == 85); #expect(m.currentReps == 5)

        let planned = flow(snap, plan: .init(exerciseNames: ["Bench Press"], prescriptions: [
            PlannedExercisePrescription(exerciseName: "Bench Press",
                                        sets: [PlannedSetPrescription(targetReps: 6, targetWeightKg: 90)])]))
        planned.startLogSet(for: planned.exerciseList[0].exercise)
        #expect(planned.currentWeight == 90); #expect(planned.currentReps == 6)
    }

    @Test func partnerNeverInheritsOwnerLoad() throws {
        addSession(day: 1, [("Bench Press", 100, 5, nil), ("Bench Press", 40, 12, sam), ("Squat", 60, 15, sam)])
        addSession(day: 2, [("Curl", 20, 15, sam)])
        let snap = try syncedSnapshot()
        let m = flow(snap, partner: sam)
        m.startLogSet(for: m.exerciseList[0].exercise)
        let d = direct(snap, performer: sam.id.uuidString, owner: false)
        #expect(m.currentWeight == d.weightKg); #expect(m.currentReps == Double(d.reps))
        #expect(m.currentWeight == 40)
    }

    @Test func partnerGeneralHistoryAndFreshPersonUseSafeFallback() throws {
        addSession(day: 1, [("Bench Press", 100, 5, nil), ("Curl", 15, 15, sam)])
        let snap = try syncedSnapshot()
        let m = flow(snap, partner: sam)
        m.startLogSet(for: m.exerciseList[0].exercise)
        let d = direct(snap, performer: sam.id.uuidString, owner: false)
        #expect(m.currentReps == Double(d.reps))
        #expect(m.currentWeight == (d.weightKg ?? 20))
        #expect(m.currentWeight != 100)

        let fresh = WatchSetDefaultSnapshot(generatedAt: now, performers: [])
        let f = flow(fresh)
        f.startLogSet(for: f.exerciseList[0].exercise)
        let fd = direct(fresh, performer: "owner", owner: true)
        #expect(f.currentWeight == (fd.weightKg ?? 20)); #expect(f.currentReps == Double(fd.reps))
    }

    /// Issue (field testing): a partner added by typed name only — no `performers:`
    /// payload linking a phone UUID, exactly the `addPartner(named:)`/name-only-start
    /// path — must still resolve that name's previous weight from synced history by
    /// matching the snapshot performer's `displayName`, not fall through to the flat
    /// 45 lb/20 kg default because the local Watch-only person has no remote id.
    @Test func nameOnlyPartnerStillGetsTheirOwnSyncedWeightNotTheFlatDefault() throws {
        addSession(day: 1, [("Bench Press", 100, 5, nil), ("Bench Press", 40, 12, sam)])
        let snap = try syncedSnapshot()
        // No `performers:` payload at all — exactly the bug's reproduction path.
        let m = WatchStrengthFlowModel(context: watch, unit: .kilograms, cooldownDefault: 5,
                                       restDefault: 90, setDefaultHistory: Provider(snapshot: snap))
        m.start(title: "Push", plannedExerciseNames: ["Bench Press"], createSession: true)
        m.addPartner(named: "Sam")
        m.selectPerformer(at: 1)
        m.startLogSet(for: m.exerciseList[0].exercise)
        #expect(m.currentWeight == 40, "name-only partner must inherit their own synced weight, not the flat default")
        #expect(m.currentWeight != 45)
    }

    @Test func changedSnapshotChangesHandshakeButIdenticalCoalesces() throws {
        addSession(day: 1, [("Bench Press", 80, 8, nil)])
        try phone.save()
        let a = try WatchSetDefaultSnapshotBuilder.make(context: phone, now: now)
        let same = try WatchSetDefaultSnapshotBuilder.make(context: phone, now: now)
        func comps(_ s: WatchSetDefaultSnapshot) -> WatchSyncHandshake.Components {
            .init(context: [WatchSync.Key.setDefaultSnapshot: s.propertyList])
        }
        #expect(comps(a) == comps(same))
        addSession(day: 2, [("Bench Press", 85, 6, nil)])
        try phone.save()
        let b = try WatchSetDefaultSnapshotBuilder.make(context: phone, now: now)
        #expect(comps(a) != comps(b))
    }
}
#endif
