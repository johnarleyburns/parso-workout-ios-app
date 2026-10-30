import XCTest
import SwiftData
@testable import CadenceFeatures
import CadenceCore

/// Issue #433: phone history → built snapshot → context round trip → persisted → Watch flow
/// chooses the same defaults the phone's `PerformerSetPlanner.resolve` inputs would.
@MainActor
final class WatchSetDefaultParityTests: XCTestCase {
    private var phone: ModelContext!
    private var watch: ModelContext!
    private var sam: Person!
    private let base = Date(timeIntervalSince1970: 1_700_000_000)
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        phone = ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
        watch = ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
        _ = try WorkoutRepository.seedStarterLibraryIfNeeded(watch)
        sam = Person(name: "Sam")
        phone.insert(sam)
    }

    private struct Provider: WatchSetDefaultHistoryProviding {
        var snapshot: WatchSetDefaultSnapshot
        func history(exerciseKey: String, performerID: String) -> PerformerSetPlanner.History {
            snapshot.history(exerciseKey: exerciseKey, performerID: performerID)
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
            phone.insert(SetEntry(weight: r.1, reps: r.2, order: i, session: s, exercise: e, performedBy: r.3))
        }
    }

    /// Phone build → context dictionary → Watch apply → persisted → relaunch load.
    private func syncedSnapshot() throws -> WatchSetDefaultSnapshot {
        try phone.save()
        let built = try WatchSetDefaultSnapshotBuilder.make(context: phone, now: now)
        let ctx = WatchSync.IncomingContext.from(
            context: [WatchSync.Key.setDefaultSnapshot: built.propertyList], applyingTo: .init())
        let received = try XCTUnwrap(ctx.setDefaultSnapshot)
        XCTAssertEqual(received, built)
        let suite = "parity-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(WatchSetDefaultSnapshotPersistence(defaults: defaults).replaceIfNewer(received), .replaced)
        // Relaunch: a fresh persistence object, phone unreachable.
        return try XCTUnwrap(WatchSetDefaultSnapshotPersistence(defaults: defaults).load())
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

    func testOwnerHistoryMatchesPhoneAfterRelaunch() throws {
        addSession(day: 1, [("Bench Press", 80, 8, nil), ("Bench Press", 80, 8, nil)])
        let snap = try syncedSnapshot()
        let m = flow(snap)
        m.startLogSet(for: m.exerciseList[0].exercise)
        let d = direct(snap, performer: "owner", owner: true)
        XCTAssertEqual(m.currentWeight, d.weightKg); XCTAssertEqual(m.currentReps, Double(d.reps))
        XCTAssertEqual(m.currentWeight, 80)
    }

    func testWatchLoggedSetThenExplicitPlan() throws {
        addSession(day: 1, [("Bench Press", 80, 8, nil)])
        let snap = try syncedSnapshot()
        let m = flow(snap)
        let ex = m.exerciseList[0].exercise
        m.startLogSet(for: ex)
        m.currentWeight = 85; m.currentReps = 5
        _ = m.logSet(); m.finishRest()
        m.startLogSet(for: ex)
        XCTAssertEqual(m.currentWeight, 85); XCTAssertEqual(m.currentReps, 5)

        let planned = flow(snap, plan: .init(exerciseNames: ["Bench Press"], prescriptions: [
            PlannedExercisePrescription(exerciseName: "Bench Press",
                                        sets: [PlannedSetPrescription(targetReps: 6, targetWeightKg: 90)])]))
        planned.startLogSet(for: planned.exerciseList[0].exercise)
        XCTAssertEqual(planned.currentWeight, 90); XCTAssertEqual(planned.currentReps, 6)
    }

    func testPartnerNeverInheritsOwnerLoad() throws {
        addSession(day: 1, [("Bench Press", 100, 5, nil), ("Bench Press", 40, 12, sam), ("Squat", 60, 15, sam)])
        addSession(day: 2, [("Curl", 20, 15, sam)])
        let snap = try syncedSnapshot()
        let m = flow(snap, partner: sam)
        m.startLogSet(for: m.exerciseList[0].exercise)
        let d = direct(snap, performer: sam.id.uuidString, owner: false)
        XCTAssertEqual(m.currentWeight, d.weightKg); XCTAssertEqual(m.currentReps, Double(d.reps))
        XCTAssertEqual(m.currentWeight, 40)
    }

    func testPartnerGeneralHistoryAndFreshPersonUseSafeFallback() throws {
        addSession(day: 1, [("Bench Press", 100, 5, nil), ("Curl", 15, 15, sam)])
        let snap = try syncedSnapshot()
        let m = flow(snap, partner: sam)
        m.startLogSet(for: m.exerciseList[0].exercise)
        let d = direct(snap, performer: sam.id.uuidString, owner: false)
        XCTAssertEqual(m.currentReps, Double(d.reps))
        XCTAssertEqual(m.currentWeight, d.weightKg ?? 20)
        XCTAssertNotEqual(m.currentWeight, 100)

        let fresh = WatchSetDefaultSnapshot(generatedAt: now, performers: [])
        let f = flow(fresh)
        f.startLogSet(for: f.exerciseList[0].exercise)
        let fd = direct(fresh, performer: "owner", owner: true)
        XCTAssertEqual(f.currentWeight, fd.weightKg ?? 20); XCTAssertEqual(f.currentReps, Double(fd.reps))
    }

    func testChangedSnapshotChangesHandshakeButIdenticalCoalesces() throws {
        addSession(day: 1, [("Bench Press", 80, 8, nil)])
        try phone.save()
        let a = try WatchSetDefaultSnapshotBuilder.make(context: phone, now: now)
        let same = try WatchSetDefaultSnapshotBuilder.make(context: phone, now: now)
        func comps(_ s: WatchSetDefaultSnapshot) -> WatchSyncHandshake.Components {
            .init(context: [WatchSync.Key.setDefaultSnapshot: s.propertyList])
        }
        XCTAssertEqual(comps(a), comps(same))
        addSession(day: 2, [("Bench Press", 85, 6, nil)])
        try phone.save()
        let b = try WatchSetDefaultSnapshotBuilder.make(context: phone, now: now)
        XCTAssertNotEqual(comps(a), comps(b))
    }
}
