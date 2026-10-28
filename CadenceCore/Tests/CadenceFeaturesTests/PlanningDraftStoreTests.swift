import XCTest
import SwiftData
import CadenceCore
@testable import CadenceFeatures

@MainActor
final class PlanningDraftStoreTests: XCTestCase {
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

    func testCreateIfNeededReusesSingleDraft() throws {
        let context = try makeContext()
        let store = PlanningDraftStore()
        XCTAssertNil(try store.currentDraft(in: context))
        let first = try store.createIfNeeded(in: context)
        let second = try store.createIfNeeded(in: context)
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(try visibleCount(context), 1)
    }

    func testSequentialAddsRetainBothAndDuplicateIsIdempotent() throws {
        let context = try makeContext()
        let store = PlanningDraftStore()
        let bench = Exercise(name: "Bench Press"), row = Exercise(name: "Row")
        var draft = try store.add(bench, to: nil, in: context)
        draft = try store.add(row, to: draft.id, in: context)
        let stamp = draft.updatedAt
        let bytes = draft.payloadData
        draft = try store.add(Exercise(name: "bench press"), to: draft.id, in: context)
        XCTAssertEqual(try names(draft), ["Bench Press", "Row"])
        XCTAssertEqual(draft.updatedAt, stamp)
        XCTAssertEqual(draft.payloadData, bytes)
        XCTAssertEqual(try visibleCount(context), 1)
    }

    func testSeedSetsUseOwnerHistoryPolicy() throws {
        let context = try makeContext()
        let history = PartnerPlanResolver.ExerciseHistory(
            lastSets: [.init(weightKg: 60, reps: 5), .init(weightKg: 60, reps: 5)])
        let store = PlanningDraftStore(historyProvider: { _, _ in history })
        let draft = try store.add(Exercise(name: "Squat"), to: nil, in: context)
        let sets = try PlanningDraftCodec.decode(draft).exercises[0].sets
        let expected = PartnerPlanResolver.ownerSeedSets(history: history, defaultReps: 10)
        XCTAssertEqual(sets.map(\.targetReps), expected.map(\.targetReps))
        XCTAssertEqual(sets.map(\.targetWeight), expected.map(\.targetWeight))
    }

    func testRemoveReorderReplaceAndDiscard() throws {
        let context = try makeContext()
        let store = PlanningDraftStore()
        var draft = try store.add(Exercise(name: "A"), to: nil, in: context)
        for n in ["B", "C"] { draft = try store.add(Exercise(name: n), to: draft.id, in: context) }
        try store.moveExercises(from: IndexSet(integer: 2), to: 0, in: draft, context: context)
        XCTAssertEqual(try names(draft), ["C", "A", "B"])
        let removeID = try PlanningDraftCodec.decode(draft).exercises[1].id
        try store.removeExercise(id: removeID, from: draft, context: context)
        XCTAssertEqual(try names(draft), ["C", "B"])
        var plan = try PlanningDraftCodec.decode(draft)
        plan.title = "Legs"
        plan.exercises = [EditableExercise(name: "Z", sets: [], notes: "")]
        try store.replacePlan(plan, in: draft, context: context)
        XCTAssertEqual(draft.title, "Legs")
        XCTAssertEqual(try names(draft), ["Z"])
        try store.discard(draft, in: context)
        XCTAssertNotNil(draft.deletedAt)
        XCTAssertNil(try store.currentDraft(in: context))
        let fresh = try store.createIfNeeded(in: context)
        XCTAssertNotEqual(fresh.id, draft.id)
        XCTAssertEqual(try visibleCount(context), 1)
    }

    func testSaveFailurePreservesPreviousDraft() throws {
        let context = try makeContext()
        let draft = try PlanningDraftStore().add(Exercise(name: "A"), to: nil, in: context)
        let bytes = draft.payloadData, stamp = draft.updatedAt, title = draft.title
        let failing = PlanningDraftStore(save: { _ in throw Boom() })
        XCTAssertThrowsError(try failing.add(Exercise(name: "B"), to: draft.id, in: context))
        XCTAssertEqual(draft.payloadData, bytes)
        XCTAssertEqual(draft.updatedAt, stamp)
        XCTAssertEqual(draft.title, title)
    }

    func testEncodeFailurePreservesPreviousDraft() throws {
        let context = try makeContext()
        let draft = try PlanningDraftStore().add(Exercise(name: "A"), to: nil, in: context)
        let bytes = draft.payloadData, stamp = draft.updatedAt
        let failing = PlanningDraftStore(encode: { _ in throw Boom() })
        XCTAssertThrowsError(try failing.add(Exercise(name: "B"), to: draft.id, in: context))
        XCTAssertEqual(draft.payloadData, bytes)
        XCTAssertEqual(draft.updatedAt, stamp)
    }

    func testLegacyDuplicatesResolveDeterministically() throws {
        let context = try makeContext()
        let payload = try PlanningDraftCodec.encode(EditablePlan(warmupMinutes: 0, cooldownMinutes: 0, exercises: []))
        let old = PlanningDraft(payloadData: payload, updatedAt: Date(timeIntervalSince1970: 100))
        let newest = PlanningDraft(payloadData: payload, updatedAt: Date(timeIntervalSince1970: 300))
        let gone = PlanningDraft(payloadData: payload, updatedAt: Date(timeIntervalSince1970: 900))
        gone.deletedAt = Date()
        [old, newest, gone].forEach(context.insert)
        try context.save()
        let store = PlanningDraftStore()
        XCTAssertEqual(try store.currentDraft(in: context)?.id, newest.id)
        let draft = try store.add(Exercise(name: "A"), to: old.id, in: context)
        XCTAssertEqual(draft.id, old.id)
        XCTAssertEqual(try visibleCount(context), 1)
        XCTAssertNotNil(newest.deletedAt)
    }
}
