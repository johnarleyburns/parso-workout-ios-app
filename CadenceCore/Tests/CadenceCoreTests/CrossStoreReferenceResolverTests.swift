import XCTest
import SwiftData
@testable import CadenceCore

@MainActor
final class CrossStoreReferenceResolverTests: XCTestCase {
    func testSetInitSnapshotsExerciseAndPartnerIdentity() {
        let exercise = Exercise(name: "Cable Row")
        let partner = Person(name: "Alex")
        let set = SetEntry(weight: 57, reps: 8, exercise: exercise, performedBy: partner)

        XCTAssertEqual(set.exerciseID, exercise.id)
        XCTAssertEqual(set.exerciseKey, ExerciseKey(raw: exercise.name).raw)
        XCTAssertEqual(set.exerciseNameSnapshot, exercise.name)
        XCTAssertEqual(set.performerID, partner.id)
    }

    func testResolverUsesIDThenKeyThenSnapshot() {
        let exercise = Exercise(name: "Cable Row")
        let resolver = CrossStoreReferenceResolver()

        let byID = SetEntry(exerciseID: exercise.id, exerciseNameSnapshot: "Old name")
        XCTAssertEqual(resolver.exercise(for: byID, exercises: [exercise]).name, "Cable Row")

        let byKey = SetEntry(exerciseKey: ExerciseKey(raw: exercise.name).raw,
                             exerciseNameSnapshot: "Old name")
        XCTAssertEqual(resolver.exercise(for: byKey, exercises: [exercise]).name, "Cable Row")

        let snapshot = SetEntry(exerciseID: UUID(), exerciseNameSnapshot: "Cable Row")
        XCTAssertEqual(resolver.exercise(for: snapshot, exercises: []).name, "Cable Row")
    }

    func testMissingPartnerBecomesSafePlaceholderAndOwnerStaysOwner() {
        let resolver = CrossStoreReferenceResolver()
        let partnerID = UUID()
        let partnerSet = SetEntry(performerID: partnerID)
        let ownerSet = SetEntry()

        let partner = resolver.performer(for: partnerSet, people: [])
        XCTAssertEqual(partner.id, partnerID)
        XCTAssertEqual(partner.name, "Partner")
        XCTAssertFalse(partner.isOwner)

        let owner = resolver.performer(for: ownerSet, people: [])
        XCTAssertNil(owner.id)
        XCTAssertEqual(owner.name, "Me")
        XCTAssertTrue(owner.isOwner)
    }

    func testRefreshBackfillsLegacySetsIdempotently() {
        let exercise = Exercise(name: "Bench Press")
        let partner = Person(name: "Sam")
        let first = SetEntry(performedBy: partner)
        first.exercise = exercise
        let second = SetEntry()
        second.exercise = exercise
        let resolver = CrossStoreReferenceResolver()

        XCTAssertEqual(resolver.refresh([first, second]), 2)
        XCTAssertEqual(resolver.refresh([first, second]), 0)
        XCTAssertEqual(first.performerID, partner.id)
        XCTAssertNil(second.performerID)
    }
}
