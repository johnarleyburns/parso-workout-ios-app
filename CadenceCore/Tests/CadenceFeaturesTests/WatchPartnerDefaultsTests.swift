import XCTest
import SwiftData
@testable import CadenceFeatures
import CadenceCore

/// Issue #432: Watch partner set defaults resolve from the partner's own synced history.
@MainActor
final class WatchPartnerDefaultsTests: XCTestCase {
    private var context: ModelContext!
    private let samA = UUID().uuidString
    private let samB = UUID().uuidString

    override func setUpWithError() throws {
        let container = try CadenceStore.makeModelContainer(inMemory: true)
        context = ModelContext(container)
        _ = try WorkoutRepository.seedStarterLibraryIfNeeded(context)
    }

    private struct Stub: WatchSetDefaultHistoryProviding {
        var snapshot: WatchSetDefaultSnapshot
        func history(exerciseKey: String, performerID: String) -> PerformerSetPlanner.History {
            snapshot.history(exerciseKey: exerciseKey, performerID: performerID)
        }
    }

    private func bench(_ kg: Double, _ reps: Int) -> [WatchSetDefaultSnapshot.Exercise] {
        [.init(id: "Bench Press", displayName: "Bench Press", repLadders: [[reps, reps]],
               samples: [.init(weightKg: kg, reps: reps)], firstWorkingWeightKg: kg)]
    }

    private func model(_ snapshot: WatchSetDefaultSnapshot, partners: [WatchSync.PerformerReference],
                       select: Int) -> WatchStrengthFlowModel {
        let m = WatchStrengthFlowModel(context: context, unit: .kilograms, cooldownDefault: 5,
                                       restDefault: 90, setDefaultHistory: Stub(snapshot: snapshot))
        m.start(title: "Push", plannedExerciseNames: ["Bench Press"],
                planPayload: WatchPlanPayload(strength: .init(exerciseNames: ["Bench Press"],
                                                              performers: [.owner()] + partners)),
                createSession: true)
        m.selectPerformer(at: select)
        return m
    }

    private func snap(_ performers: [WatchSetDefaultSnapshot.Performer]) -> WatchSetDefaultSnapshot {
        WatchSetDefaultSnapshot(generatedAt: Date(timeIntervalSince1970: 1_000), performers: performers)
    }

    private func sam(_ id: String) -> WatchSync.PerformerReference {
        .init(id: id, displayName: "Sam", isOwner: false)
    }

    func testOwnerAndPartnerGetOwnHistoryAndSwitchRecalculates() {
        let s = snap([.init(id: "owner", displayName: "Me", exercises: bench(125, 8), generalRepLadders: []),
                      .init(id: samA, displayName: "Sam", exercises: bench(65, 12), generalRepLadders: [])])
        let m = model(s, partners: [sam(samA)], select: 0)
        let ex = m.exerciseList[0].exercise
        m.startLogSet(for: ex)
        XCTAssertEqual(m.currentWeight, 125); XCTAssertEqual(m.currentReps, 8)
        m.selectPerformer(at: 1)
        m.startLogSet(for: ex)
        XCTAssertEqual(m.currentWeight, 65); XCTAssertEqual(m.currentReps, 12)
        m.selectPerformer(at: 0)
        m.startLogSet(for: ex)
        XCTAssertEqual(m.currentWeight, 125)
    }

    func testPartnerWithoutHistoryNeverGetsOwnerLoad() {
        let s = snap([.init(id: "owner", displayName: "Me", exercises: bench(125, 8), generalRepLadders: [])])
        let m = model(s, partners: [sam(samA)], select: 1)
        m.startLogSet(for: m.exerciseList[0].exercise)
        XCTAssertEqual(m.currentWeight, 20)
    }

    func testPartnerGeneralRepsDefaultWithoutInventedWeight() {
        let s = snap([.init(id: "owner", displayName: "Me", exercises: bench(125, 8), generalRepLadders: []),
                      .init(id: samA, displayName: "Sam", exercises: [], generalRepLadders: [[20, 20, 20]])])
        let m = model(s, partners: [sam(samA)], select: 1)
        m.startLogSet(for: m.exerciseList[0].exercise)
        XCTAssertEqual(m.currentReps, 20)
        XCTAssertEqual(m.currentWeight, 20) // generic fallback, not history
    }

    func testPartnerExplicitPlanOverridesHistory() throws {
        let s = snap([.init(id: samA, displayName: "Sam", exercises: bench(65, 12), generalRepLadders: [])])
        let m = model(s, partners: [sam(samA)], select: 1)
        let session = try XCTUnwrap(m.session)
        let localID = try XCTUnwrap(m.activePerformer.localPerson?.id)
        session.plannedPerformerPrescriptions = [.init(performerID: localID.uuidString, exercises: [
            PlannedExercisePrescription(exerciseName: "Bench Press",
                                        sets: [PlannedSetPrescription(targetReps: 5, targetWeightKg: 50)])])]
        m.startLogSet(for: m.exerciseList[0].exercise)
        XCTAssertEqual(m.currentWeight, 50); XCTAssertEqual(m.currentReps, 5)
    }

    func testSameNamedPartnersStayIsolated() {
        let s = snap([.init(id: samA, displayName: "Sam", exercises: bench(60, 10), generalRepLadders: []),
                      .init(id: samB, displayName: "Sam", exercises: bench(90, 5), generalRepLadders: [])])
        let m = model(s, partners: [sam(samA), sam(samB)], select: 1)
        let ex = m.exerciseList[0].exercise
        m.startLogSet(for: ex)
        XCTAssertEqual(m.currentWeight, 60)
        m.selectPerformer(at: 2)
        m.startLogSet(for: ex)
        XCTAssertEqual(m.currentWeight, 90); XCTAssertEqual(m.currentReps, 5)
    }

    func testLegacyNamePartnerCannotMatchSnapshotByName() {
        let s = snap([.init(id: "sam", displayName: "Sam", exercises: bench(60, 10), generalRepLadders: [])])
        let m = WatchStrengthFlowModel(context: context, unit: .kilograms, cooldownDefault: 5,
                                       restDefault: 90, setDefaultHistory: Stub(snapshot: s))
        m.start(title: "Push", plannedExerciseNames: ["Bench Press"], initialPartnerNames: ["Sam"],
                createSession: true)
        m.selectPerformer(at: 1)
        m.startLogSet(for: m.exerciseList[0].exercise)
        XCTAssertEqual(m.currentWeight, 20)
    }
}
