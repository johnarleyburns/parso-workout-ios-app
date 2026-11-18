#if canImport(SwiftData)
import Testing
import SwiftData
@testable import CadenceCore

/// Strength logging / history-edit fixes: opt-in partner roster (empty = solo),
/// non-clobbering set edits, set re-attribution, and changing an entry's exercise.
@MainActor
struct StrengthEditingTests {

    private func makeContext() throws -> ModelContext {
        let container = try CadenceStore.makeModelContainer(inMemory: true)
        return ModelContext(container)
    }

    // MARK: SessionRoster — partners are opt-in (empty = solo)

    @Test func emptyPartnerIDsMeansSolo() throws {
        let ctx = try makeContext()
        let me = try WorkoutRepository.me(in: ctx)
        let sam = try WorkoutRepository.findOrCreatePerson(named: "Sam", in: ctx)
        let people = [me, sam]

        // No partners scoped -> solo, even though Sam exists in the database.
        #expect(SessionRoster.scopedPartners(activePartnerIDs: [], allPeople: people).isEmpty)
        #expect(SessionRoster.roster(activePartnerIDs: [], allPeople: people).map(\.id) == [me.id])
        #expect(!SessionRoster.hasPartners(activePartnerIDs: [], allPeople: people))
    }

    @Test func scopedPartnersAreIncluded() throws {
        let ctx = try makeContext()
        let me = try WorkoutRepository.me(in: ctx)
        let sam = try WorkoutRepository.findOrCreatePerson(named: "Sam", in: ctx)
        let alex = try WorkoutRepository.findOrCreatePerson(named: "Alex", in: ctx)
        let people = [me, sam, alex]

        let scoped = SessionRoster.scopedPartners(activePartnerIDs: [sam.id.uuidString], allPeople: people)
        #expect(scoped.map(\.id) == [sam.id])
        #expect(SessionRoster.hasPartners(activePartnerIDs: [sam.id.uuidString], allPeople: people))
        // Owner is always first in the roster.
        let roster = SessionRoster.roster(activePartnerIDs: [sam.id.uuidString], allPeople: people)
        #expect(roster.first?.id == me.id)
        #expect(roster.count == 2)
    }

    @Test func attributableIncludesAlreadyAttributedPartner() throws {
        let ctx = try makeContext()
        let me = try WorkoutRepository.me(in: ctx)
        let sam = try WorkoutRepository.findOrCreatePerson(named: "Sam", in: ctx)
        let people = [me, sam]

        // Sam is NOT scoped, but a set is already attributed to Sam (e.g. a
        // mis-attributed past set). The performer picker must still offer Sam so
        // it can be corrected back to "Me".
        let attributable = SessionRoster.attributablePartners(
            activePartnerIDs: [], allPeople: people, includingAttributed: [sam.id])
        #expect(attributable.map(\.id) == [sam.id])
        #expect(SessionRoster.canAttribute(
            activePartnerIDs: [], allPeople: people, attributedIDs: [sam.id]))
        #expect(!SessionRoster.canAttribute(
            activePartnerIDs: [], allPeople: people, attributedIDs: []))
    }

    // MARK: updateSet — no-clobber + reassignment

    @Test func updateSetPreservesWarmupAndNoteWhenOmitted() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)
        let set = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 60, reps: 5,
                                               rpe: 8, isWarmup: true, note: "felt easy", in: ctx)

        // Edit only weight + reps; warmup flag, note, and RPE must be untouched.
        try WorkoutRepository.updateSet(set, weightKg: 65, reps: 8, in: ctx)
        #expect(set.weight == 65)
        #expect(set.reps == 8)
        #expect(set.isWarmup, "warm-up flag must survive a weight/reps edit")
        #expect(set.note == "felt easy", "note must survive a weight/reps edit")
        #expect(set.rpe == 8, "RPE must survive a weight/reps edit")
    }

    @Test func updateSetReassignsPerformer() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)
        let me = try WorkoutRepository.me(in: ctx)
        let sam = try WorkoutRepository.findOrCreatePerson(named: "Sam", in: ctx)
        let set = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 100, reps: 5,
                                               performedBy: sam, in: ctx)
        #expect(!set.isOwnerSet)

        // Correct the partner label back to "Me" — owner Person normalizes to nil.
        try WorkoutRepository.updateSet(set, performedBy: .some(me), in: ctx)
        #expect(set.performedBy == nil)
        #expect(set.isOwnerSet)

        // Attribute to a partner again.
        try WorkoutRepository.updateSet(set, performedBy: .some(sam), in: ctx)
        #expect(set.performedBy?.id == sam.id)
    }

    // MARK: changeExercise — move a whole card to another movement

    @Test func changeExerciseMovesAllSetsAndUpdatesPlannedNames() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)
        let incline = try WorkoutRepository.findOrCreateExercise(named: "Incline Bench Press", in: ctx)
        session.plannedExerciseNames = ["Bench Press"]
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 80, reps: 8, in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 80, reps: 6, in: ctx)

        let moved = try WorkoutRepository.changeExercise(in: session, from: bench, to: incline, in: ctx)
        #expect(moved == 2)
        #expect(session.orderedSets.allSatisfy { $0.exercise?.id == incline.id })
        #expect(session.exercisesInOrder.map(\.name) == ["Incline Bench Press"])
        #expect(session.plannedExerciseNames == ["Incline Bench Press"])
    }

    @Test func changeExerciseNoOpForSameExercise() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 80, reps: 8, in: ctx)
        let moved = try WorkoutRepository.changeExercise(in: session, from: bench, to: bench, in: ctx)
        #expect(moved == 0)
        #expect(session.orderedSets.count == 1)
    }
}
#endif
