#if canImport(SwiftData)
import Foundation
import Testing
import SwiftData
import CadenceCore
import CadencePhoneFeatures
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

@MainActor
struct PlanningDraftStoreTests {
    private struct Boom: Error {}

    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    private func visibleCount(_ context: ModelContext) throws -> Int {
        try context.fetch(FetchDescriptor<PlanningDraft>()).filter(\.isVisible).count
    }

    private func names(_ draft: PlanningDraft) throws -> [String] {
        try PlanningDraftCodec.decode(draft).exercises.map(\.name)
    }

    @Test func createIfNeededReusesSingleDraft() throws {
        let context = try makeContext()
        let store = PlanningDraftStore()
        #expect(try store.currentDraft(in: context) == nil)
        let first = try store.createIfNeeded(in: context)
        let second = try store.createIfNeeded(in: context)
        #expect(first.id == second.id)
        #expect(try visibleCount(context) == 1)
    }

    @Test func sequentialAddsRetainBothAndDuplicateIsIdempotent() throws {
        let context = try makeContext()
        let store = PlanningDraftStore()
        let bench = Exercise(name: "Bench Press"), row = Exercise(name: "Row")
        var draft = try store.add(bench, to: nil, in: context)
        draft = try store.add(row, to: draft.id, in: context)
        let stamp = draft.updatedAt
        let bytes = draft.payloadData
        draft = try store.add(Exercise(name: "bench press"), to: draft.id, in: context)
        #expect(try names(draft) == ["Bench Press", "Row"])
        #expect(draft.updatedAt == stamp)
        #expect(draft.payloadData == bytes)
        #expect(try visibleCount(context) == 1)
    }

    @Test func seedSetsUseOwnerHistoryPolicy() throws {
        let context = try makeContext()
        let history = PartnerPlanResolver.ExerciseHistory(
            lastSets: [.init(weightKg: 60, reps: 5), .init(weightKg: 60, reps: 5)])
        let store = PlanningDraftStore(historyProvider: { _, _ in history })
        let draft = try store.add(Exercise(name: "Squat"), to: nil, in: context)
        let sets = try PlanningDraftCodec.decode(draft).exercises[0].sets
        let expected = PartnerPlanResolver.ownerSeedSets(history: history, defaultReps: 10)
        #expect(sets.map(\.targetReps) == expected.map(\.targetReps))
        #expect(sets.map(\.targetWeight) == expected.map(\.targetWeight))
    }

    @Test func removeReorderReplaceAndDiscard() throws {
        let context = try makeContext()
        let store = PlanningDraftStore()
        var draft = try store.add(Exercise(name: "A"), to: nil, in: context)
        for n in ["B", "C"] { draft = try store.add(Exercise(name: n), to: draft.id, in: context) }
        try store.moveExercises(from: IndexSet(integer: 2), to: 0, in: draft, context: context)
        #expect(try names(draft) == ["C", "A", "B"])
        let removeID = try PlanningDraftCodec.decode(draft).exercises[1].id
        try store.removeExercise(id: removeID, from: draft, context: context)
        #expect(try names(draft) == ["C", "B"])
        var plan = try PlanningDraftCodec.decode(draft)
        plan.title = "Legs"
        plan.exercises = [EditableExercise(name: "Z", sets: [], notes: "")]
        try store.replacePlan(plan, in: draft, context: context)
        #expect(draft.title == "Legs")
        #expect(try names(draft) == ["Z"])
        try store.discard(draft, in: context)
        #expect(draft.deletedAt != nil)
        #expect(try store.currentDraft(in: context) == nil)
        let fresh = try store.createIfNeeded(in: context)
        #expect(fresh.id != draft.id)
        #expect(try visibleCount(context) == 1)
    }

    @Test func saveFailurePreservesPreviousDraft() throws {
        let context = try makeContext()
        let draft = try PlanningDraftStore().add(Exercise(name: "A"), to: nil, in: context)
        let bytes = draft.payloadData, stamp = draft.updatedAt, title = draft.title
        let failing = PlanningDraftStore(save: { _ in throw Boom() })
        #expect(throws: (any Error).self) { try failing.add(Exercise(name: "B"), to: draft.id, in: context) }
        #expect(draft.payloadData == bytes)
        #expect(draft.updatedAt == stamp)
        #expect(draft.title == title)
    }

    @Test func encodeFailurePreservesPreviousDraft() throws {
        let context = try makeContext()
        let draft = try PlanningDraftStore().add(Exercise(name: "A"), to: nil, in: context)
        let bytes = draft.payloadData, stamp = draft.updatedAt
        let failing = PlanningDraftStore(encode: { _ in throw Boom() })
        #expect(throws: (any Error).self) { try failing.add(Exercise(name: "B"), to: draft.id, in: context) }
        #expect(draft.payloadData == bytes)
        #expect(draft.updatedAt == stamp)
    }

    @Test func legacyDuplicatesResolveDeterministically() throws {
        let context = try makeContext()
        let payload = try PlanningDraftCodec.encode(EditablePlan(warmupMinutes: 0, cooldownMinutes: 0, exercises: []))
        let old = PlanningDraft(payloadData: payload, updatedAt: Date(timeIntervalSince1970: 100))
        let newest = PlanningDraft(payloadData: payload, updatedAt: Date(timeIntervalSince1970: 300))
        let gone = PlanningDraft(payloadData: payload, updatedAt: Date(timeIntervalSince1970: 900))
        gone.deletedAt = Date()
        [old, newest, gone].forEach(context.insert)
        try context.save()
        let store = PlanningDraftStore()
        #expect(try store.currentDraft(in: context)?.id == newest.id)
        let draft = try store.add(Exercise(name: "A"), to: old.id, in: context)
        #expect(draft.id == old.id)
        #expect(try visibleCount(context) == 1)
        #expect(newest.deletedAt != nil)
    }

    @Test func countAndMembershipIgnoreDuplicateAdds() throws {
        let context = try makeContext()
        let store = PlanningDraftStore()
        let draft = try store.add(Exercise(name: "Squat"), to: nil, in: context)
        _ = try store.add(Exercise(name: "squat"), to: nil, in: context)
        _ = try store.add(Exercise(name: "Row"), to: nil, in: context)
        #expect(try store.exerciseCount(for: draft) == 2)
        #expect(try store.contains(exerciseNamed: "SQUAT", in: draft))
        #expect(!(try store.contains(exerciseNamed: "Press", in: draft)))
        #expect(try store.exerciseNames(for: draft) == ["Squat", "Row"])
    }
}
#endif
