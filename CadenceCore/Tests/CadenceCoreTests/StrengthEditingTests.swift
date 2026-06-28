import XCTest
import SwiftData
@testable import CadenceCore

/// Strength logging / history-edit fixes: opt-in partner roster (empty = solo),
/// non-clobbering set edits, set re-attribution, and changing an entry's exercise.
@MainActor
final class StrengthEditingTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let container = try CadenceStore.makeModelContainer(inMemory: true)
        return ModelContext(container)
    }

    // MARK: SessionRoster — partners are opt-in (empty = solo)

    func testEmptyPartnerIDsMeansSolo() throws {
        let ctx = try makeContext()
        let me = try WorkoutRepository.me(in: ctx)
        let sam = try WorkoutRepository.findOrCreatePerson(named: "Sam", in: ctx)
        let people = [me, sam]

        // No partners scoped -> solo, even though Sam exists in the database.
        XCTAssertTrue(SessionRoster.scopedPartners(activePartnerIDs: [], allPeople: people).isEmpty)
        XCTAssertEqual(SessionRoster.roster(activePartnerIDs: [], allPeople: people).map(\.id), [me.id])
        XCTAssertFalse(SessionRoster.hasPartners(activePartnerIDs: [], allPeople: people))
    }

    func testScopedPartnersAreIncluded() throws {
        let ctx = try makeContext()
        let me = try WorkoutRepository.me(in: ctx)
        let sam = try WorkoutRepository.findOrCreatePerson(named: "Sam", in: ctx)
        let alex = try WorkoutRepository.findOrCreatePerson(named: "Alex", in: ctx)
        let people = [me, sam, alex]

        let scoped = SessionRoster.scopedPartners(activePartnerIDs: [sam.id.uuidString], allPeople: people)
        XCTAssertEqual(scoped.map(\.id), [sam.id])
        XCTAssertTrue(SessionRoster.hasPartners(activePartnerIDs: [sam.id.uuidString], allPeople: people))
        // Owner is always first in the roster.
        let roster = SessionRoster.roster(activePartnerIDs: [sam.id.uuidString], allPeople: people)
        XCTAssertEqual(roster.first?.id, me.id)
        XCTAssertEqual(roster.count, 2)
    }

    func testAttributableIncludesAlreadyAttributedPartner() throws {
        let ctx = try makeContext()
        let me = try WorkoutRepository.me(in: ctx)
        let sam = try WorkoutRepository.findOrCreatePerson(named: "Sam", in: ctx)
        let people = [me, sam]

        // Sam is NOT scoped, but a set is already attributed to Sam (e.g. a
        // mis-attributed past set). The performer picker must still offer Sam so
        // it can be corrected back to "Me".
        let attributable = SessionRoster.attributablePartners(
            activePartnerIDs: [], allPeople: people, includingAttributed: [sam.id])
        XCTAssertEqual(attributable.map(\.id), [sam.id])
        XCTAssertTrue(SessionRoster.canAttribute(
            activePartnerIDs: [], allPeople: people, attributedIDs: [sam.id]))
        XCTAssertFalse(SessionRoster.canAttribute(
            activePartnerIDs: [], allPeople: people, attributedIDs: []))
    }

    // MARK: updateSet — no-clobber + reassignment

    func testUpdateSetPreservesWarmupAndNoteWhenOmitted() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)
        let set = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 60, reps: 5,
                                               rpe: 8, isWarmup: true, note: "felt easy", in: ctx)

        // Edit only weight + reps; warmup flag, note, and RPE must be untouched.
        try WorkoutRepository.updateSet(set, weightKg: 65, reps: 8, in: ctx)
        XCTAssertEqual(set.weight, 65)
        XCTAssertEqual(set.reps, 8)
        XCTAssertTrue(set.isWarmup, "warm-up flag must survive a weight/reps edit")
        XCTAssertEqual(set.note, "felt easy", "note must survive a weight/reps edit")
        XCTAssertEqual(set.rpe, 8, "RPE must survive a weight/reps edit")
    }

    func testUpdateSetReassignsPerformer() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)
        let me = try WorkoutRepository.me(in: ctx)
        let sam = try WorkoutRepository.findOrCreatePerson(named: "Sam", in: ctx)
        let set = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 100, reps: 5,
                                               performedBy: sam, in: ctx)
        XCTAssertFalse(set.isOwnerSet)

        // Correct the partner label back to "Me" — owner Person normalizes to nil.
        try WorkoutRepository.updateSet(set, performedBy: .some(me), in: ctx)
        XCTAssertNil(set.performedBy)
        XCTAssertTrue(set.isOwnerSet)

        // Attribute to a partner again.
        try WorkoutRepository.updateSet(set, performedBy: .some(sam), in: ctx)
        XCTAssertEqual(set.performedBy?.id, sam.id)
    }

    // MARK: changeExercise — move a whole card to another movement

    func testChangeExerciseMovesAllSetsAndUpdatesPlannedNames() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)
        let incline = try WorkoutRepository.findOrCreateExercise(named: "Incline Bench Press", in: ctx)
        session.plannedExerciseNames = ["Bench Press"]
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 80, reps: 8, in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 80, reps: 6, in: ctx)

        let moved = try WorkoutRepository.changeExercise(in: session, from: bench, to: incline, in: ctx)
        XCTAssertEqual(moved, 2)
        XCTAssertTrue(session.orderedSets.allSatisfy { $0.exercise?.id == incline.id })
        XCTAssertEqual(session.exercisesInOrder.map(\.name), ["Incline Bench Press"])
        XCTAssertEqual(session.plannedExerciseNames, ["Incline Bench Press"])
    }

    func testChangeExerciseNoOpForSameExercise() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 80, reps: 8, in: ctx)
        let moved = try WorkoutRepository.changeExercise(in: session, from: bench, to: bench, in: ctx)
        XCTAssertEqual(moved, 0)
        XCTAssertEqual(session.orderedSets.count, 1)
    }
}
