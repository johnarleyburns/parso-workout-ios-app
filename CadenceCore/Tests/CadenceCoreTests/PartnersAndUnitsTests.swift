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
}
