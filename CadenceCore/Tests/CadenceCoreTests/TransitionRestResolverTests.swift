import Testing
import Foundation
@testable import CadenceCore

@Suite struct TransitionRestResolverTests {
    private func ex(_ n: String, sets: Int, rest: Int? = nil, def: Int? = nil,
                    trans: Int? = nil, group: String? = nil,
                    warmups: Int = 0) -> PlannedExercisePrescription {
        let s = (0..<warmups).map { _ in PlannedSetPrescription(targetReps: 5, restSeconds: nil, isWarmup: true) }
            + (0..<sets).map { _ in PlannedSetPrescription(targetReps: 5, restSeconds: rest) }
        return PlannedExercisePrescription(sourceItemID: nil, exerciseKey: nil, exerciseName: n,
                                           sets: s, supersetGroup: group,
                                           defaultRestSeconds: def, transitionRestSeconds: trans)
    }

    @Test func setVersusTransitionAndLast() {
        let p = [ex("A", sets: 2, rest: 60, trans: 120), ex("B", sets: 1, trans: 30)]
        #expect(TransitionRestResolver.restAfterSet(prescriptions: p, exerciseName: "A", completedSetCount: 1, isWarmup: false, fallbackSeconds: 90) == 60)
        #expect(TransitionRestResolver.restAfterSet(prescriptions: p, exerciseName: "A", completedSetCount: 2, isWarmup: false, fallbackSeconds: 90) == 120)
        #expect(TransitionRestResolver.restAfterSet(prescriptions: p, exerciseName: "B", completedSetCount: 1, isWarmup: false, fallbackSeconds: 90) == nil)
    }

    @Test func legacyAbsentTransitionKeepsSetRest() {
        let p = [ex("A", sets: 2, rest: 75), ex("B", sets: 1)]
        #expect(TransitionRestResolver.restAfterSet(prescriptions: p, exerciseName: "A", completedSetCount: 2, isWarmup: false, fallbackSeconds: 90) == 75)
        let d = [ex("A", sets: 2, def: 45), ex("B", sets: 1)]
        #expect(TransitionRestResolver.restAfterSet(prescriptions: d, exerciseName: "A", completedSetCount: 2, isWarmup: false, fallbackSeconds: 90) == 45)
        #expect(TransitionRestResolver.restAfterSet(prescriptions: [ex("A", sets: 2), ex("B", sets: 1)], exerciseName: "A", completedSetCount: 2, isWarmup: false, fallbackSeconds: 90) == 90)
    }

    @Test func warmupSupersetAndUnknown() {
        let p = [ex("A", sets: 1, trans: 99, group: "g", warmups: 1), ex("B", sets: 1, group: "g"), ex("C", sets: 1)]
        #expect(TransitionRestResolver.restAfterSet(prescriptions: p, exerciseName: "A", completedSetCount: 1, isWarmup: true, fallbackSeconds: 90) == nil)
        #expect(TransitionRestResolver.restAfterSet(prescriptions: p, exerciseName: "A", completedSetCount: 1, isWarmup: false, fallbackSeconds: 90) == nil)
        #expect(TransitionRestResolver.restAfterSet(prescriptions: p, exerciseName: "Z", completedSetCount: 1, isWarmup: false, fallbackSeconds: 90) == 90)
    }

    @Test func editRecalculatesOnlyFutureAndLegacyDecode() throws {
        var p = [ex("A", sets: 3, rest: 60, trans: 120), ex("B", sets: 1)]
        let before = TransitionRestResolver.upcomingRests(prescriptions: p, completedCountByExercise: ["A": 1], fallbackSeconds: 90)
        #expect(before["A"]! == [60, 120])
        p[0].transitionRestSeconds = 200
        let after = TransitionRestResolver.upcomingRests(prescriptions: p, completedCountByExercise: ["A": 3], fallbackSeconds: 90)
        #expect(after["A"]!.isEmpty)
        let legacy = Data(#"{"exerciseName":"A","sets":[{"targetReps":5}]}"#.utf8)
        let d = try JSONDecoder().decode(PlannedExercisePrescription.self, from: legacy)
        #expect(d.transitionRestSeconds == nil)
        let rt = try JSONDecoder().decode(PlannedExercisePrescription.self, from: JSONEncoder().encode(p[0]))
        #expect(rt == p[0])
    }

    @Test func snapshotCarriesPolicy() throws {
        let item = StrengthItem(exerciseKey: ExerciseKey(raw: "a"), order: 0, defaultRestSeconds: 50,
                                sets: [PrescribedSet(setIndex: 0, repTarget: .exact(5))],
                                transitionRestSeconds: 140)
        let snap = StrengthItemSnapshot(id: item.id, exerciseKey: "a", exerciseName: "A", sets: [],
                                        defaultRestSeconds: item.defaultRestSeconds,
                                        transitionRestSeconds: item.transitionRestSeconds)
        #expect(snap.transitionRestSeconds == 140 && snap.defaultRestSeconds == 50)
    }
}
