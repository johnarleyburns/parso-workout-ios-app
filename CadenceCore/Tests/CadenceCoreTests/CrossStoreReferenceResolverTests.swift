import Testing
import Foundation
#if canImport(SwiftData)
import SwiftData
#endif
@testable import CadenceCore

@MainActor
@Suite final class CrossStoreReferenceResolverTests {
    @Test func setInitSnapshotsExerciseAndPartnerIdentity() {
        let exercise = Exercise(name: "Cable Row")
        let partner = Person(name: "Alex")
        let set = SetEntry(weight: 57, reps: 8, exercise: exercise, performedBy: partner)

        #expect(set.exerciseID == exercise.id)
        #expect(set.exerciseKey == ExerciseKey(raw: exercise.name).raw)
        #expect(set.exerciseNameSnapshot == exercise.name)
        #expect(set.performerID == partner.id)
    }

    @Test func resolverUsesIDThenKeyThenSnapshot() {
        let exercise = Exercise(name: "Cable Row")
        let resolver = CrossStoreReferenceResolver()

        let byID = SetEntry(exerciseID: exercise.id, exerciseNameSnapshot: "Old name")
        #expect(resolver.exercise(for: byID, exercises: [exercise]).name == "Cable Row")

        let byKey = SetEntry(exerciseKey: ExerciseKey(raw: exercise.name).raw,
                             exerciseNameSnapshot: "Old name")
        #expect(resolver.exercise(for: byKey, exercises: [exercise]).name == "Cable Row")

        let snapshot = SetEntry(exerciseID: UUID(), exerciseNameSnapshot: "Cable Row")
        #expect(resolver.exercise(for: snapshot, exercises: []).name == "Cable Row")
    }

    @Test func missingPartnerBecomesSafePlaceholderAndOwnerStaysOwner() {
        let resolver = CrossStoreReferenceResolver()
        let partnerID = UUID()
        let partnerSet = SetEntry(performerID: partnerID)
        let ownerSet = SetEntry()

        let partner = resolver.performer(for: partnerSet, people: [])
        #expect(partner.id == partnerID)
        #expect(partner.name == "Partner")
        #expect(!partner.isOwner)

        let owner = resolver.performer(for: ownerSet, people: [])
        #expect(owner.id == nil)
        #expect(owner.name == "Me")
        #expect(owner.isOwner)
    }

    @Test func refreshBackfillsLegacySetsIdempotently() {
        let exercise = Exercise(name: "Bench Press")
        let partner = Person(name: "Sam")
        let first = SetEntry(performedBy: partner)
        first.exercise = exercise
        let second = SetEntry()
        second.exercise = exercise
        let resolver = CrossStoreReferenceResolver()

        #expect(resolver.refresh([first, second]) == 2)
        #expect(resolver.refresh([first, second]) == 0)
        #expect(first.performerID == partner.id)
        #expect(second.performerID == nil)
    }
}
