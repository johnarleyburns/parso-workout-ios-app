import XCTest
import SwiftData
@testable import CadenceCore

/// Field-testing §04 — partners (owner-only stats), dual-unit entry, reuse.
final class PartnersAndUnitsTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let container = try CadenceStore.makeModelContainer(inMemory: true)
        return ModelContext(container)
    }

    // MARK: Dual-unit entry (decisions #4/#15)

    func testOppositeUnitAutoFillIsExact() {
        let (unit, value) = UnitEntry.opposite(of: 100, unit: .pounds)
        XCTAssertEqual(unit, .kilograms)
        XCTAssertEqual(value, 45.359, accuracy: 0.01)   // 100 lb → 45.36 kg
        let back = UnitEntry.opposite(of: value, unit: .kilograms)
        XCTAssertEqual(back.unit, .pounds)
        XCTAssertEqual(back.value, 100, accuracy: 0.01)
    }

    func testKilogramsCanonical() {
        XCTAssertEqual(UnitEntry.kilograms(60, unit: .kilograms), 60, accuracy: 0.001)
        XCTAssertEqual(UnitEntry.kilograms(135, unit: .pounds), 61.235, accuracy: 0.01)
    }

    func testPlateRoundingOptional() {
        // 137 lb → nearest 2.5 lb = 137.5 lb.
        let kg = UnitEntry.kilograms(137, unit: .pounds)
        let rounded = UnitEntry.plateRounded(kg: kg, unit: .pounds, increment: 2.5)
        XCTAssertEqual(WorkoutMath.display(rounded, in: .pounds), 137.5, accuracy: 0.01)
    }

    // MARK: Partner attribution & owner-only stats (decision #13)

    func testPartnerSetsExcludedFromOwnerStats() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)
        let sam = try WorkoutRepository.findOrCreatePerson(named: "Sam", in: ctx)

        // Owner logs 100 kg; partner logs a heavier 140 kg.
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 100, reps: 5, in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 140, reps: 5,
                                         performedBy: sam, in: ctx)

        // Owner PR must reflect only the owner's 100 kg, not Sam's 140 kg.
        let pr = WorkoutRepository.currentPR(for: bench, rule: .topWeight, formula: .epley)
        XCTAssertEqual(pr ?? 0, 100, accuracy: 0.001)
        // Session volume excludes the partner set.
        XCTAssertEqual(session.totalVolume, WorkoutMath.volume(weight: 100, reps: 5), accuracy: 0.001)
        // Owner last-time excludes the partner set too.
        let lastTime = WorkoutRepository.lastTimeSets(for: bench, excluding: nil)
        XCTAssertTrue(lastTime.allSatisfy { $0.isOwnerSet })
    }

    /// Field-test issue #4: training with a partner must never inflate the
    /// owner's coach counts. Owner does 4 hard sets of hack squat, partner does 4
    /// of the same — every coach-facing count (event, weekly sets by part, weekly
    /// balance) must read 4, never 8.
    func testPartnerSetsExcludedFromCoachVolumeCounts() throws {
        let ctx = try makeContext()
        let now = Date()
        let when = now.addingTimeInterval(-1800)
        let session = try WorkoutRepository.createSession(date: when, in: ctx)
        let hackSquat = try WorkoutRepository.findOrCreateExercise(
            named: "Hack Squat", primaryMuscles: ["quadriceps"], in: ctx)
        let sam = try WorkoutRepository.findOrCreatePerson(named: "Sam", in: ctx)

        for _ in 0..<4 {
            _ = try WorkoutRepository.addSet(to: session, exercise: hackSquat, weightKg: 120, reps: 8,
                                             rpe: 8, completedAt: when, in: ctx)
        }
        for _ in 0..<4 {
            _ = try WorkoutRepository.addSet(to: session, exercise: hackSquat, weightKg: 120, reps: 8,
                                             rpe: 8, completedAt: when, performedBy: sam, in: ctx)
        }
        session.endedAt = now

        let event = TrainingEvent.from(session: session)!
        guard case .strength(let details) = event.kind, let d = details else {
            return XCTFail("expected a strength event")
        }
        XCTAssertEqual(d.totalHardSets, 4, "Only the owner's 4 sets should count, not the partner's")
        XCTAssertEqual(d.exercises.first?.hardSetCount, 4)

        let tf = TrainingFacts.make(sessions: [session], now: now,
                                    goal: .strength, experience: .intermediate)
        // Under DB++ one set credits several groups (direct 1.0 + indirect 0.5), so
        // the cross-group total is no longer the set count. The direct credit is:
        // 4 owner sets of a quad movement = 4.0 quadriceps, and would read 8.0 if
        // the partner's sets leaked in.
        XCTAssertEqual(tf.weeklySetsByGroup[.quadriceps] ?? 0, 4, accuracy: 0.001,
                       "Direct weekly credit must count only the owner's 4 sets")

        let facts = CoachFacts.make(from: [event], goal: .strength, experience: .intermediate, now: now)
        XCTAssertEqual(facts.weeklyBalance.fractionalSets.values.reduce(0, +), 4, accuracy: 0.001,
                       "Coach weekly balance must count only the owner's 4 sets")
    }

    func testNilAttributionIsOwner() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)
        let set = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 80, reps: 5, in: ctx)
        XCTAssertTrue(set.isOwnerSet)
        XCTAssertEqual(session.totalVolume, WorkoutMath.volume(weight: 80, reps: 5), accuracy: 0.001)
    }

    func testFindOrCreatePersonDeduplicates() throws {
        let ctx = try makeContext()
        let a = try WorkoutRepository.findOrCreatePerson(named: "Alex", in: ctx)
        let b = try WorkoutRepository.findOrCreatePerson(named: "alex", in: ctx)
        XCTAssertEqual(a.id, b.id)
        let me = try WorkoutRepository.me(in: ctx)
        XCTAssertTrue(me.isMe)
        XCTAssertNotEqual(me.id, a.id)
    }

    func testSessionRosterPreservesExplicitOrderWithOwnerNotFirst() throws {
        let ctx = try makeContext()
        let me = try WorkoutRepository.me(in: ctx)
        let sam = try WorkoutRepository.findOrCreatePerson(named: "Sam", in: ctx)
        let alex = try WorkoutRepository.findOrCreatePerson(named: "Alex", in: ctx)
        let people = [alex, me, sam]

        let roster = SessionRoster.roster(
            activePartnerIDs: [sam.id.uuidString, me.id.uuidString, alex.id.uuidString],
            allPeople: people)

        XCTAssertEqual(roster.map(\.name), ["Sam", "Me", "Alex"])
        XCTAssertEqual(SessionRoster.scopedPartners(
            activePartnerIDs: [sam.id.uuidString, me.id.uuidString, alex.id.uuidString],
            allPeople: people).map(\.name), ["Sam", "Alex"])
    }

    func testPartnerSpecificPriorWeightLookupUsesPerformer() throws {
        let ctx = try makeContext()
        let me = try WorkoutRepository.me(in: ctx)
        let sam = try WorkoutRepository.findOrCreatePerson(named: "Sam", in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)

        let prior = try WorkoutRepository.createSession(date: Date(timeIntervalSince1970: 1_000), in: ctx)
        _ = try WorkoutRepository.addSet(to: prior, exercise: bench, weightKg: 130, reps: 5, in: ctx)
        _ = try WorkoutRepository.addSet(to: prior, exercise: bench, weightKg: 85, reps: 8,
                                         performedBy: sam, in: ctx)

        let today = try WorkoutRepository.createSession(date: Date(timeIntervalSince1970: 2_000), in: ctx)
        XCTAssertEqual(
            WorkoutRepository.firstWorkingSetWeight(for: bench, performedBy: me, excluding: today),
            130)
        XCTAssertEqual(
            WorkoutRepository.firstWorkingSetWeight(for: bench, performedBy: nil, excluding: today),
            130)
        XCTAssertEqual(
            WorkoutRepository.firstWorkingSetWeight(for: bench, performedBy: sam, excluding: today),
            85)
    }

    // MARK: Reuse workout (decision #16)

    func testReuseSessionClonesExercisesWithoutSets() throws {
        let ctx = try makeContext()
        let past = try WorkoutRepository.createSession(title: "Push Day", in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)
        let ohp = try WorkoutRepository.findOrCreateExercise(named: "Overhead Press", in: ctx)
        _ = try WorkoutRepository.addSet(to: past, exercise: bench, weightKg: 100, reps: 5, in: ctx)
        _ = try WorkoutRepository.addSet(to: past, exercise: ohp, weightKg: 60, reps: 5, in: ctx)

        let fresh = try WorkoutRepository.reuseSession(from: past, in: ctx)
        XCTAssertEqual(fresh.title, "Push Day")
        XCTAssertTrue(fresh.orderedSets.isEmpty, "reused session starts with no sets")
        XCTAssertEqual(fresh.plannedExerciseNames, ["Bench Press", "Overhead Press"])
    }

    // feedback batch 3 — "start from history" should carry a partner's movements
    // too (the user often trains with the same partner), so reuse no longer drops
    // exercises that only the partner performed.
    func testReuseSessionIncludesPartnerExercises() throws {
        let ctx = try makeContext()
        let past = try WorkoutRepository.createSession(title: "Bench Day", in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)
        let curl = try WorkoutRepository.findOrCreateExercise(named: "Barbell Curl", in: ctx)
        let sam = try WorkoutRepository.findOrCreatePerson(named: "Sam", in: ctx)
        _ = try WorkoutRepository.addSet(to: past, exercise: bench, weightKg: 100, reps: 5, in: ctx)
        // Curl was only ever done by the partner.
        _ = try WorkoutRepository.addSet(to: past, exercise: curl, weightKg: 20, reps: 12, performedBy: sam, in: ctx)

        let fresh = try WorkoutRepository.reuseSession(from: past, in: ctx)
        XCTAssertEqual(fresh.plannedExerciseNames, ["Bench Press", "Barbell Curl"])
    }

    func testCopyWorkoutDuplicatesExercisesAndSets() throws {
        let ctx = try makeContext()
        let past = try WorkoutRepository.createSession(title: "Push Day", in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)
        _ = try WorkoutRepository.addSet(to: past, exercise: bench, weightKg: 100, reps: 5, in: ctx)
        _ = try WorkoutRepository.addSet(to: past, exercise: bench, weightKg: 102.5, reps: 5, in: ctx)

        let fresh = try WorkoutRepository.createSession(in: ctx)
        let copied = try WorkoutRepository.copyWorkout(from: past, into: fresh, in: ctx)
        XCTAssertEqual(copied, 2)
        XCTAssertEqual(fresh.orderedSets.count, 2, "sets are duplicated, not just exercises")
        XCTAssertEqual(fresh.title, "Push Day")
        XCTAssertEqual(fresh.orderedSets.first?.weight, 100)
    }

    // MARK: Export carries partner tag (decision #14)

    func testExportTagsPartnerSets() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)
        let sam = try WorkoutRepository.findOrCreatePerson(named: "Sam", in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 100, reps: 5, in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 90, reps: 5,
                                         performedBy: sam, in: ctx)

        let export = try WorkoutRepository.buildExport(ctx)
        let sets = export.sessions.flatMap(\.sets)
        XCTAssertTrue(sets.contains { $0.performedBy == nil })   // owner
        XCTAssertTrue(sets.contains { $0.performedBy == "Sam" }) // partner tagged
        XCTAssertTrue(DataExport.encodeCSV(export).contains("performed_by"))
    }

    func testActivePartnerIDsRoundTrip() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(in: ctx)
        let id1 = UUID().uuidString
        let id2 = UUID().uuidString
        session.activePartnerIDs = [id1, id2]
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<WorkoutSession>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].activePartnerIDs.count, 2)
        XCTAssertTrue(fetched[0].activePartnerIDs.contains(id1))
        XCTAssertTrue(fetched[0].activePartnerIDs.contains(id2))
    }

    func testCreateSessionPropagatesPartnerIDs() throws {
        let ctx = try makeContext()
        let ids = [UUID().uuidString, UUID().uuidString]
        let session = try WorkoutRepository.createSession(partnerIDs: ids, in: ctx)
        XCTAssertEqual(session.activePartnerIDs.count, 2)
        XCTAssertEqual(Set(session.activePartnerIDs), Set(ids))
    }

    // MARK: - Explicit plans (field test 2026-08-19 #1)

    /// `explicitPlannedSets` must distinguish "the user planned this" from
    /// "nobody said" — that is the whole basis for letting a plan outrank history.
    func testExplicitPlannedSetsDistinguishesPlannedFromAbsent() throws {
        let ctx = try makeContext()
        let partnerID = UUID()
        let other = UUID()
        let session = try WorkoutRepository.createSession(in: ctx)
        session.plannedPrescriptions = [PlannedExercisePrescription(
            exerciseName: "Bench Press",
            sets: [PlannedSetPrescription(targetReps: 5, targetWeightKg: 100)])]
        session.plannedPerformerPrescriptions = [
            PlannedPerformerPrescription(performerID: nil, exercises: session.plannedPrescriptions),
            PlannedPerformerPrescription(performerID: partnerID.uuidString, exercises: [
                PlannedExercisePrescription(
                    exerciseName: "Bench Press",
                    sets: [PlannedSetPrescription(targetReps: 20, targetWeightKg: 20)])])
        ]

        XCTAssertEqual(session.explicitPlannedSets(forPerformerID: nil, exerciseName: "bench press")?
                        .map(\.targetReps), [5], "Matching is case-insensitive")
        XCTAssertEqual(session.explicitPlannedSets(forPerformerID: partnerID, exerciseName: "Bench Press")?
                        .map(\.targetWeightKg), [20])
        XCTAssertNil(session.explicitPlannedSets(forPerformerID: other, exerciseName: "Bench Press"),
                     "A partner with no stored entry has no explicit plan of their own")
        XCTAssertNil(session.explicitPlannedSets(forPerformerID: partnerID, exerciseName: "Back Squat"),
                     "…nor does a movement the plan never mentioned")
    }

    /// A legacy session with only the owner's plan still reports it as explicit.
    func testExplicitPlannedSetsFallsBackToTheOwnerPlanForTheOwnerOnly() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(in: ctx)
        session.plannedExerciseNames = ["Back Squat"]
        session.plannedRepLadder = [12, 10, 8]

        XCTAssertEqual(session.explicitPlannedSets(forPerformerID: nil, exerciseName: "Back Squat")?
                        .map(\.targetReps), [12, 10, 8])
        XCTAssertNil(session.explicitPlannedSets(forPerformerID: UUID(), exerciseName: "Back Squat"))
    }
}
