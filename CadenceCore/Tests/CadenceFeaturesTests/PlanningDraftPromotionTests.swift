import XCTest
import SwiftData
import CadenceCore
@testable import CadenceFeatures

@MainActor
final class PlanningDraftPromotionTests: XCTestCase {
    private struct Boom: Error {}

    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    private func richDraft(_ store: PlanningDraftStore, _ context: ModelContext) throws -> PlanningDraft {
        let partner = UUID()
        let group = SupersetGroupID(raw: "A")
        let plan = EditablePlan(
            title: "Push", warmupMinutes: 0, cooldownMinutes: 0,
            exercises: [
                EditableExercise(name: "Bench Press",
                                 sets: [EditableSet(targetReps: 5, targetWeight: 60, loadMode: .straight, oneRepMaxPercent: nil)],
                                 notes: "RIR 2",
                                 performerPlans: [EditablePerformerPlan(performerID: partner, name: "P",
                                     sets: [EditableSet(targetReps: 8, targetWeight: 40, loadMode: .straight, oneRepMaxPercent: nil)])],
                                 supersetGroup: group),
                EditableExercise(name: "Row",
                                 sets: [EditableSet(targetReps: 10, targetWeight: 50, loadMode: .percentageOfOneRepMax, oneRepMaxPercent: 70)],
                                 notes: "", supersetGroup: group)
            ],
            partnerIDs: [partner], enginePlanId: "plan", engineRevisionId: "rev")
        let draft = try store.createIfNeeded(in: context)
        try store.replacePlan(plan, in: draft, context: context)
        return draft
    }

    private func visible(_ context: ModelContext) throws -> Int {
        try context.fetch(FetchDescriptor<PlanningDraft>()).filter(\.isVisible).count
    }

    private var future: Date { Calendar.current.date(byAdding: .day, value: 3, to: Date())! }

    func testScheduleCreatesOneRowRetiresDraftAndIsIdempotent() throws {
        let context = try makeContext(), store = PlanningDraftStore()
        let draft = try richDraft(store, context)
        let op = UUID()
        let first = try store.schedule(draftID: draft.id, for: future, operationID: op, in: context)
        let again = try store.schedule(draftID: draft.id, for: future, operationID: op, in: context)
        XCTAssertTrue(first === again)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ScheduledWorkout>()).count, 1)
        XCTAssertEqual(try visible(context), 0)
        let plan = try ScheduledWorkoutStore.decode(first.payloadData, version: first.payloadVersion)
        XCTAssertEqual(plan.exercises.map(\.name), ["Bench Press", "Row"])
        XCTAssertEqual(plan.exercises[0].performerPlans.count, 1)
    }

    func testScheduleSaveFailurePreservesDraft() throws {
        let context = try makeContext()
        let draft = try richDraft(PlanningDraftStore(), context)
        let failing = PlanningDraftStore(save: { _ in throw Boom() })
        XCTAssertThrowsError(try failing.schedule(draftID: draft.id, for: future, operationID: UUID(), in: context))
        XCTAssertNil(draft.deletedAt)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ScheduledWorkout>()).filter { $0.modelContext != nil }.count, 0)
    }

    func testSchedulePastDateAndMissingDraftFail() throws {
        let context = try makeContext(), store = PlanningDraftStore()
        let draft = try richDraft(store, context)
        let past = Calendar.current.date(byAdding: .day, value: -3, to: Date())!
        XCTAssertThrowsError(try store.schedule(draftID: draft.id, for: past, operationID: UUID(), in: context))
        XCTAssertNil(draft.deletedAt)
        XCTAssertThrowsError(try store.schedule(draftID: UUID(), for: future, operationID: UUID(), in: context))
    }

    func testStartMapsPlanAndIsIdempotent() throws {
        let context = try makeContext(), store = PlanningDraftStore()
        let draft = try richDraft(store, context)
        let plan = try PlanningDraftCodec.decode(draft)
        let op = UUID()
        let session = try store.start(draftID: draft.id, operationID: op, in: context)
        let again = try store.start(draftID: draft.id, operationID: op, in: context)
        XCTAssertTrue(session === again)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutSession>()).count, 1)
        XCTAssertEqual(try visible(context), 0)
        XCTAssertEqual(session.id, op)
        XCTAssertEqual(session.plannedExerciseNames, ["Bench Press", "Row"])
        XCTAssertEqual(session.plannedPrescriptions.map(\.supersetGroup), ["A", "A"])
        XCTAssertEqual(session.plannedPrescriptions[1].sets.first?.targetLoadMode, EditableLoadMode.percentageOfOneRepMax.rawValue)
        XCTAssertEqual(session.plannedPerformerPrescriptions.count, plan.performerPrescriptions().count)
        XCTAssertEqual(session.enginePlanId, "plan")
        XCTAssertEqual(session.engineRevisionId, "rev")
        XCTAssertEqual(session.notes, "RIR 2")
        XCTAssertEqual(session.activePartnerIDs, plan.partnerIDs.map(\.uuidString))
    }

    func testStartSaveFailurePreservesDraftAndLeavesNoSession() throws {
        let context = try makeContext()
        let draft = try richDraft(PlanningDraftStore(), context)
        let failing = PlanningDraftStore(save: { _ in throw Boom() })
        XCTAssertThrowsError(try failing.start(draftID: draft.id, operationID: UUID(), in: context))
        XCTAssertNil(draft.deletedAt)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutSession>()).count, 0)
    }

    func testStartRetryAfterInterruptedRetireFinishesRetiring() throws {
        let context = try makeContext(), store = PlanningDraftStore()
        let draft = try richDraft(store, context)
        let op = UUID()
        context.insert(WorkoutSession(id: op, title: "Push"))
        try context.save()
        let session = try store.start(draftID: draft.id, operationID: op, in: context)
        XCTAssertEqual(session.id, op)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutSession>()).count, 1)
        XCTAssertEqual(try visible(context), 0)
    }

    func testUndecodablePayloadPreservesDraft() throws {
        let context = try makeContext(), store = PlanningDraftStore()
        let draft = try richDraft(store, context)
        draft.payloadVersion = 99
        XCTAssertThrowsError(try store.start(draftID: draft.id, operationID: UUID(), in: context))
        XCTAssertThrowsError(try store.schedule(draftID: draft.id, for: future, operationID: UUID(), in: context))
        XCTAssertNil(draft.deletedAt)
    }

    func testDiscardByIDRetiresAndFailureRestores() throws {
        let context = try makeContext()
        let draft = try richDraft(PlanningDraftStore(), context)
        let failing = PlanningDraftStore(save: { _ in throw Boom() })
        XCTAssertThrowsError(try failing.discard(draftID: draft.id, in: context))
        XCTAssertNil(draft.deletedAt)
        try PlanningDraftStore().discard(draftID: draft.id, in: context)
        XCTAssertEqual(try visible(context), 0)
    }
}
