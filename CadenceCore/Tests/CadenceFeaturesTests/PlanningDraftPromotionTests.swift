#if canImport(SwiftData)
import Foundation
import Testing
import SwiftData
import CadenceCore
import CadencePhoneFeatures
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

@MainActor
struct PlanningDraftPromotionTests {
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

    @Test func undecodablePayloadPreservesDraftOnStart() throws {
        let context = try makeContext(), store = PlanningDraftStore()
        let draft = try richDraft(store, context)
        draft.payloadVersion = 99
        #expect(throws: (any Error).self) { try store.start(draftID: draft.id, operationID: UUID(), in: context) }
        #expect(draft.deletedAt == nil)
        #expect(try context.fetch(FetchDescriptor<WorkoutSession>()).count == 0)
    }

    @Test func startMapsPlanAndIsIdempotent() throws {
        let context = try makeContext(), store = PlanningDraftStore()
        let draft = try richDraft(store, context)
        let plan = try PlanningDraftCodec.decode(draft)
        let op = UUID()
        let session = try store.start(draftID: draft.id, operationID: op, in: context)
        let again = try store.start(draftID: draft.id, operationID: op, in: context)
        #expect(session === again)
        #expect(try context.fetch(FetchDescriptor<WorkoutSession>()).count == 1)
        #expect(try visible(context) == 0)
        #expect(session.id == op)
        #expect(session.plannedExerciseNames == ["Bench Press", "Row"])
        #expect(session.plannedPrescriptions.map(\.supersetGroup) == ["A", "A"])
        #expect(session.plannedPrescriptions[1].sets.first?.targetLoadMode == EditableLoadMode.percentageOfOneRepMax.rawValue)
        #expect(session.plannedPerformerPrescriptions.count == plan.performerPrescriptions().count)
        #expect(session.enginePlanId == "plan")
        #expect(session.engineRevisionId == "rev")
        #expect(session.notes == "RIR 2")
        #expect(session.activePartnerIDs == plan.partnerIDs.map(\.uuidString))
    }

    @Test func startSaveFailurePreservesDraftAndLeavesNoSession() throws {
        let context = try makeContext()
        let draft = try richDraft(PlanningDraftStore(), context)
        let failing = PlanningDraftStore(save: { _ in throw Boom() })
        #expect(throws: (any Error).self) { try failing.start(draftID: draft.id, operationID: UUID(), in: context) }
        #expect(draft.deletedAt == nil)
        #expect(try context.fetch(FetchDescriptor<WorkoutSession>()).count == 0)
    }

    @Test func startRetryAfterInterruptedRetireFinishesRetiring() throws {
        let context = try makeContext(), store = PlanningDraftStore()
        let draft = try richDraft(store, context)
        let op = UUID()
        context.insert(WorkoutSession(id: op, title: "Push"))
        try context.save()
        let session = try store.start(draftID: draft.id, operationID: op, in: context)
        #expect(session.id == op)
        #expect(try context.fetch(FetchDescriptor<WorkoutSession>()).count == 1)
        #expect(try visible(context) == 0)
    }


    @Test func discardByIDRetiresAndFailureRestores() throws {
        let context = try makeContext()
        let draft = try richDraft(PlanningDraftStore(), context)
        let failing = PlanningDraftStore(save: { _ in throw Boom() })
        #expect(throws: (any Error).self) { try failing.discard(draftID: draft.id, in: context) }
        #expect(draft.deletedAt == nil)
        try PlanningDraftStore().discard(draftID: draft.id, in: context)
        #expect(try visible(context) == 0)
    }
}
#endif
