#if canImport(SwiftData)
import Foundation
import Testing
import SwiftData
@testable import CadenceCore

/// Field-testing §04 — partners (owner-only stats), dual-unit entry, reuse.
struct PartnersAndUnitsTests {

    private func makeContext() throws -> ModelContext {
        let container = try CadenceStore.makeModelContainer(inMemory: true)
        return ModelContext(container)
    }

    // MARK: Dual-unit entry (decisions #4/#15)

    @Test func oppositeUnitAutoFillIsExact() {
        let (unit, value) = UnitEntry.opposite(of: 100, unit: .pounds)
        #expect(unit == .kilograms)
        #expect(abs(value - 45.359) <= 0.01)   // 100 lb → 45.36 kg
        let back = UnitEntry.opposite(of: value, unit: .kilograms)
        #expect(back.unit == .pounds)
        #expect(abs(back.value - 100) <= 0.01)
    }

    @Test func kilogramsCanonical() {
        #expect(abs(UnitEntry.kilograms(60, unit: .kilograms) - 60) <= 0.001)
        #expect(abs(UnitEntry.kilograms(135, unit: .pounds) - 61.235) <= 0.01)
    }

    @Test func plateRoundingOptional() {
        // 137 lb → nearest 2.5 lb = 137.5 lb.
        let kg = UnitEntry.kilograms(137, unit: .pounds)
        let rounded = UnitEntry.plateRounded(kg: kg, unit: .pounds, increment: 2.5)
        #expect(abs(WorkoutMath.display(rounded, in: .pounds) - 137.5) <= 0.01)
    }

    // MARK: Partner attribution & owner-only stats (decision #13)

    @Test func partnerSetsExcludedFromOwnerStats() throws {
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
        #expect(abs((pr ?? 0) - 100) <= 0.001)
        // Session volume excludes the partner set.
        #expect(abs(session.totalVolume - WorkoutMath.volume(weight: 100, reps: 5)) <= 0.001)
        // Owner last-time excludes the partner set too.
        let lastTime = WorkoutRepository.lastTimeSets(for: bench, excluding: nil)
        #expect(lastTime.allSatisfy { $0.isOwnerSet })
    }

    /// Field-test issue #4: training with a partner must never inflate the
    /// owner's coach counts. Owner does 4 hard sets of hack squat, partner does 4
    /// of the same — every coach-facing count (event, weekly sets by part, weekly
    /// balance) must read 4, never 8.
    @Test func partnerSetsExcludedFromCoachVolumeCounts() throws {
        let ctx = try makeContext()
        // A fixed Wednesday noon: with the real clock, a run just after midnight on Monday put the
        // sets "30 minutes ago" in the previous week and the weekly counts read 0 (CI, 2026-10-05).
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 12))!
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
            Issue.record("expected a strength event")
            return
        }
        #expect(d.totalHardSets == 4, "Only the owner's 4 sets should count, not the partner's")
        #expect(d.exercises.first?.hardSetCount == 4)

        let tf = TrainingFacts.make(sessions: [session], now: now,
                                    goal: .strength, experience: .intermediate)
        // Under DB++ one set credits several groups (direct 1.0 + indirect 0.5), so
        // the cross-group total is no longer the set count. The direct credit is:
        // 4 owner sets of a quad movement = 4.0 quadriceps, and would read 8.0 if
        // the partner's sets leaked in.
        #expect(abs((tf.weeklySetsByGroup[.quadriceps] ?? 0) - 4) <= 0.001,
                       "Direct weekly credit must count only the owner's 4 sets")

        let facts = CoachFacts.make(from: [event], goal: .strength, experience: .intermediate, now: now)
        #expect(abs(facts.weeklyBalance.fractionalSets.values.reduce(0, +) - 4) <= 0.001,
                       "Coach weekly balance must count only the owner's 4 sets")
    }

    @Test func nilAttributionIsOwner() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)
        let set = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 80, reps: 5, in: ctx)
        #expect(set.isOwnerSet)
        #expect(abs(session.totalVolume - WorkoutMath.volume(weight: 80, reps: 5)) <= 0.001)
    }

    @Test func findOrCreatePersonDeduplicates() throws {
        let ctx = try makeContext()
        let a = try WorkoutRepository.findOrCreatePerson(named: "Alex", in: ctx)
        let b = try WorkoutRepository.findOrCreatePerson(named: "alex", in: ctx)
        #expect(a.id == b.id)
        let me = try WorkoutRepository.me(in: ctx)
        #expect(me.isMe)
        #expect(me.id != a.id)
    }

    @Test func sessionRosterPreservesExplicitOrderWithOwnerNotFirst() throws {
        let ctx = try makeContext()
        let me = try WorkoutRepository.me(in: ctx)
        let sam = try WorkoutRepository.findOrCreatePerson(named: "Sam", in: ctx)
        let alex = try WorkoutRepository.findOrCreatePerson(named: "Alex", in: ctx)
        let people = [alex, me, sam]

        let roster = SessionRoster.roster(
            activePartnerIDs: [sam.id.uuidString, me.id.uuidString, alex.id.uuidString],
            allPeople: people)

        #expect(roster.map(\.name) == ["Sam", "Me", "Alex"])
        #expect(SessionRoster.scopedPartners(
            activePartnerIDs: [sam.id.uuidString, me.id.uuidString, alex.id.uuidString],
            allPeople: people).map(\.name) == ["Sam", "Alex"])
    }

    @Test func partnerSpecificPriorWeightLookupUsesPerformer() throws {
        let ctx = try makeContext()
        let me = try WorkoutRepository.me(in: ctx)
        let sam = try WorkoutRepository.findOrCreatePerson(named: "Sam", in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)

        let prior = try WorkoutRepository.createSession(date: Date(timeIntervalSince1970: 1_000), in: ctx)
        _ = try WorkoutRepository.addSet(to: prior, exercise: bench, weightKg: 130, reps: 5, in: ctx)
        _ = try WorkoutRepository.addSet(to: prior, exercise: bench, weightKg: 85, reps: 8,
                                         performedBy: sam, in: ctx)

        let today = try WorkoutRepository.createSession(date: Date(timeIntervalSince1970: 2_000), in: ctx)
        #expect(
            WorkoutRepository.firstWorkingSetWeight(for: bench, performedBy: me, excluding: today)
            == 130)
        #expect(
            WorkoutRepository.firstWorkingSetWeight(for: bench, performedBy: nil, excluding: today)
            == 130)
        #expect(
            WorkoutRepository.firstWorkingSetWeight(for: bench, performedBy: sam, excluding: today)
            == 85)
    }

    // MARK: Reuse workout (decision #16)

    @Test func reuseSessionClonesExercisesWithoutSets() throws {
        let ctx = try makeContext()
        let past = try WorkoutRepository.createSession(title: "Push Day", in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)
        let ohp = try WorkoutRepository.findOrCreateExercise(named: "Overhead Press", in: ctx)
        _ = try WorkoutRepository.addSet(to: past, exercise: bench, weightKg: 100, reps: 5, in: ctx)
        _ = try WorkoutRepository.addSet(to: past, exercise: ohp, weightKg: 60, reps: 5, in: ctx)

        let fresh = try WorkoutRepository.reuseSession(from: past, in: ctx)
        #expect(fresh.title == "Push Day")
        #expect(fresh.orderedSets.isEmpty, "reused session starts with no sets")
        #expect(fresh.plannedExerciseNames == ["Bench Press", "Overhead Press"])
    }

    // feedback batch 3 — "start from history" should carry a partner's movements
    // too (the user often trains with the same partner), so reuse no longer drops
    // exercises that only the partner performed.
    @Test func reuseSessionIncludesPartnerExercises() throws {
        let ctx = try makeContext()
        let past = try WorkoutRepository.createSession(title: "Bench Day", in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)
        let curl = try WorkoutRepository.findOrCreateExercise(named: "Barbell Curl", in: ctx)
        let sam = try WorkoutRepository.findOrCreatePerson(named: "Sam", in: ctx)
        _ = try WorkoutRepository.addSet(to: past, exercise: bench, weightKg: 100, reps: 5, in: ctx)
        // Curl was only ever done by the partner.
        _ = try WorkoutRepository.addSet(to: past, exercise: curl, weightKg: 20, reps: 12, performedBy: sam, in: ctx)

        let fresh = try WorkoutRepository.reuseSession(from: past, in: ctx)
        #expect(fresh.plannedExerciseNames == ["Bench Press", "Barbell Curl"])
    }

    @Test func copyWorkoutDuplicatesExercisesAndSets() throws {
        let ctx = try makeContext()
        let past = try WorkoutRepository.createSession(title: "Push Day", in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)
        _ = try WorkoutRepository.addSet(to: past, exercise: bench, weightKg: 100, reps: 5, in: ctx)
        _ = try WorkoutRepository.addSet(to: past, exercise: bench, weightKg: 102.5, reps: 5, in: ctx)

        let fresh = try WorkoutRepository.createSession(in: ctx)
        let copied = try WorkoutRepository.copyWorkout(from: past, into: fresh, in: ctx)
        #expect(copied == 2)
        #expect(fresh.orderedSets.count == 2, "sets are duplicated, not just exercises")
        #expect(fresh.title == "Push Day")
        #expect(fresh.orderedSets.first?.weight == 100)
    }

    // MARK: Export carries partner tag (decision #14)

    @Test func exportTagsPartnerSets() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)
        let sam = try WorkoutRepository.findOrCreatePerson(named: "Sam", in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 100, reps: 5, in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 90, reps: 5,
                                         performedBy: sam, in: ctx)

        let export = try WorkoutRepository.buildExport(ctx)
        let sets = export.sessions.flatMap(\.sets)
        #expect(sets.contains { $0.performedBy == nil })   // owner
        #expect(sets.contains { $0.performedBy == "Sam" }) // partner tagged
        #expect(DataExport.encodeCSV(export).contains("performed_by"))
    }

    @Test func activePartnerIDsRoundTrip() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(in: ctx)
        let id1 = UUID().uuidString
        let id2 = UUID().uuidString
        session.activePartnerIDs = [id1, id2]
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<WorkoutSession>())
        #expect(fetched.count == 1)
        #expect(fetched[0].activePartnerIDs.count == 2)
        #expect(fetched[0].activePartnerIDs.contains(id1))
        #expect(fetched[0].activePartnerIDs.contains(id2))
    }

    @Test func createSessionPropagatesPartnerIDs() throws {
        let ctx = try makeContext()
        let ids = [UUID().uuidString, UUID().uuidString]
        let session = try WorkoutRepository.createSession(partnerIDs: ids, in: ctx)
        #expect(session.activePartnerIDs.count == 2)
        #expect(Set(session.activePartnerIDs) == Set(ids))
    }

    // MARK: - Explicit plans (field test 2026-08-19 #1)

    /// `explicitPlannedSets` must distinguish "the user planned this" from
    /// "nobody said" — that is the whole basis for letting a plan outrank history.
    @Test func explicitPlannedSetsDistinguishesPlannedFromAbsent() throws {
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

        #expect(session.explicitPlannedSets(forPerformerID: nil, exerciseName: "bench press")?
                        .map(\.targetReps) == [5], "Matching is case-insensitive")
        #expect(session.explicitPlannedSets(forPerformerID: partnerID, exerciseName: "Bench Press")?
                        .map(\.targetWeightKg) == [20])
        #expect(session.explicitPlannedSets(forPerformerID: other, exerciseName: "Bench Press") == nil,
                     "A partner with no stored entry has no explicit plan of their own")
        #expect(session.explicitPlannedSets(forPerformerID: partnerID, exerciseName: "Back Squat") == nil,
                     "…nor does a movement the plan never mentioned")
    }

    /// A legacy session with only the owner's plan still reports it as explicit.
    @Test func explicitPlannedSetsFallsBackToTheOwnerPlanForTheOwnerOnly() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(in: ctx)
        session.plannedExerciseNames = ["Back Squat"]
        session.plannedRepLadder = [12, 10, 8]

        #expect(session.explicitPlannedSets(forPerformerID: nil, exerciseName: "Back Squat")?
                        .map(\.targetReps) == [12, 10, 8])
        #expect(session.explicitPlannedSets(forPerformerID: UUID(), exerciseName: "Back Squat") == nil)
    }
}
#endif
