import XCTest
import SwiftData
import CadenceCore
import CadenceFeatures

@MainActor
final class SessionViewModelTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let container = try CadenceStore.makeModelContainer(inMemory: true)
        return ModelContext(container)
    }

    // MARK: Pure (no store)

    func testPlannedRepsUsesLadderRung() {
        XCTAssertEqual(SessionViewModel.plannedReps(ladder: [5, 4, 3], setIndex: 1,
                                                    currentSessionReps: [], priorSessionLadders: [],
                                                    lastLoggedReps: nil), 4)
    }

    func testPlannedRepsFallsBackToLastLogged() {
        XCTAssertEqual(SessionViewModel.plannedReps(ladder: nil, setIndex: 0,
                                                    currentSessionReps: [], priorSessionLadders: [],
                                                    lastLoggedReps: 8), 8)
    }

    func testPlannedRepsDefaultsToFive() {
        XCTAssertEqual(SessionViewModel.plannedReps(ladder: nil, setIndex: 0,
                                                    currentSessionReps: [], priorSessionLadders: [],
                                                    lastLoggedReps: nil), 5)
    }

    func testPlannedRepsPatternGuess() {
        // 12-10-8 pattern; two logged this session → set 3 (index 2) guesses 8.
        XCTAssertEqual(SessionViewModel.plannedReps(ladder: nil, setIndex: 2,
                                                    currentSessionReps: [12, 10],
                                                    priorSessionLadders: [[12, 10, 8]],
                                                    lastLoggedReps: 10), 8)
    }

    func testCanonicalKgKilograms() {
        XCTAssertEqual(SessionViewModel.canonicalKg(input: "100", unit: .kilograms, plateRounding: false), 100, accuracy: 0.001)
    }

    func testCanonicalKgPounds() {
        let kg = SessionViewModel.canonicalKg(input: "100", unit: .pounds, plateRounding: false)
        XCTAssertEqual(kg, WorkoutMath.canonical(100, from: .pounds), accuracy: 0.001)
    }

    func testCanonicalKgBadInputIsZero() {
        XCTAssertEqual(SessionViewModel.canonicalKg(input: "abc", unit: .kilograms, plateRounding: false), 0)
    }

    // MARK: Store-backed

    func testIsBodyweight() throws {
        let ctx = try makeContext()
        let bw = Exercise(name: "Pull-up"); bw.equipment = Equipment.bodyweight.rawValue
        let bb = Exercise(name: "Bench"); bb.equipment = Equipment.barbell.rawValue
        ctx.insert(bw); ctx.insert(bb)
        XCTAssertTrue(SessionViewModel.isBodyweight(bw))
        XCTAssertFalse(SessionViewModel.isBodyweight(bb))
    }

    func testEffectiveLadderAndPlannedSetCount() throws {
        let ctx = try makeContext()
        let s = WorkoutSession(title: "X", date: Date()); ctx.insert(s)
        XCTAssertNil(SessionViewModel.effectiveLadder(session: s))
        XCTAssertEqual(SessionViewModel.plannedSetCount(session: s), 0)
        s.plannedRepLadder = [12, 10, 8]
        XCTAssertEqual(SessionViewModel.effectiveLadder(session: s), [12, 10, 8])
        XCTAssertEqual(SessionViewModel.plannedSetCount(session: s), 3)
    }

    func testPlannedOnlyNamesExcludesLogged() throws {
        let ctx = try makeContext()
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", category: .push, in: ctx)
        let s = WorkoutSession(title: "X", date: Date()); ctx.insert(s)
        s.plannedExerciseNames = ["Bench Press", "Back Squat"]
        ctx.insert(SetEntry(weight: 100, reps: 5, order: 0, completedAt: s.date, session: s, exercise: bench))
        try ctx.save()
        XCTAssertEqual(SessionViewModel.plannedOnlyNames(session: s), ["Back Squat"])
    }

    func testLastSessionWeight() throws {
        let ctx = try makeContext()
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", category: .push, in: ctx)
        let s = WorkoutSession(title: "X", date: Date()); ctx.insert(s)
        ctx.insert(SetEntry(weight: 80, reps: 5, order: 0, completedAt: s.date, session: s, exercise: bench))
        ctx.insert(SetEntry(weight: 85, reps: 5, order: 1, completedAt: s.date, session: s, exercise: bench))
        try ctx.save()
        XCTAssertEqual(SessionViewModel.lastSessionWeight(session: s, exercise: bench, performerID: nil), 85)
    }

    func testIsPrescribedMovement() throws {
        let ctx = try makeContext()
        let s = WorkoutSession(title: "X", date: Date()); ctx.insert(s)
        s.plannedExerciseNames = ["Back Squat"]
        s.prescribedLoadKg = 100
        XCTAssertTrue(SessionViewModel.isPrescribedMovement("Back Squat", session: s))
        XCTAssertFalse(SessionViewModel.isPrescribedMovement("Bench Press", session: s))
    }

    func testPrescriptionNoPlanUsesChosenLadderAndLoad() throws {
        let ctx = try makeContext()
        let s = WorkoutSession(title: "X", date: Date()); ctx.insert(s)
        s.plannedRepLadder = [5, 5, 5]
        s.plannedExerciseNames = ["Back Squat"]
        s.prescribedLoadKg = 100
        let line = SessionViewModel.prescription(for: "Back Squat", session: s, plan: nil, unit: .kilograms)
        XCTAssertNotNil(line)
        XCTAssertTrue(line!.contains("5-5-5 reps"))
        XCTAssertTrue(line!.contains("100"))
    }

    func testPrescriptionNilWhenNothingPlanned() throws {
        let ctx = try makeContext()
        let s = WorkoutSession(title: "X", date: Date()); ctx.insert(s)
        XCTAssertNil(SessionViewModel.prescription(for: "Anything", session: s, plan: nil, unit: .kilograms))
    }
}
