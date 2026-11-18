#if canImport(SwiftData)
import Foundation
import Testing
import SwiftData
import CadenceCore
import CadencePhoneFeatures
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

struct PlanningDraftTests {
    private func fullPlan() -> EditablePlan {
        let partner = UUID()
        let sets = [
            EditableSet(targetReps: 5, targetWeight: 100),
            EditableSet(targetReps: 8, targetWeight: 60, loadMode: .percentageOfOneRepMax, oneRepMaxPercent: 75),
            EditableSet(targetReps: 12, targetWeight: nil, loadMode: .bodyweight)
        ]
        return EditablePlan(
            title: "Push", warmupMinutes: 7, cooldownMinutes: 3,
            exercises: [
                EditableExercise(name: "Bench Press", sets: sets, notes: "≤2 RIR",
                                 performerPlans: [
                                    EditablePerformerPlan(performerID: nil, name: "Me", sets: sets),
                                    EditablePerformerPlan(performerID: partner, name: "Sam",
                                                          sets: [EditableSet(targetReps: 10, targetWeight: 40)])],
                                 supersetGroup: SupersetGroupID(raw: "A")),
                EditableExercise(name: "Row", sets: [EditableSet(targetReps: 10, targetWeight: 50)],
                                 notes: "", supersetGroup: SupersetGroupID(raw: "A"))
            ],
            partnerIDs: [partner], enginePlanId: "p1", engineRevisionId: "r1",
            enginePlanJSON: Data([1, 2, 3]), suggestedWorkoutStyle: .powerlifting,
            recommendationRationale: SuggestedWorkoutRationale(
                whyWorkout: "why",
                exercises: [SuggestedExerciseRationale(exerciseName: "Row", whyExercise: "a", whySetRep: "b")]))
    }

    @Test func roundTripPreservesEveryField() throws {
        let plan = fullPlan()
        let data = try PlanningDraftCodec.encode(plan)
        let decoded = try PlanningDraftCodec.decode(data, version: PlanningDraftPayload.currentVersion)
        #expect(decoded == plan)
        let decodedPayload = EditablePlanPayload(decoded)
        let planPayload = EditablePlanPayload(plan)
        #expect(decodedPayload == planPayload)
    }

    @Test func unknownVersionThrows() throws {
        let data = try PlanningDraftCodec.encode(fullPlan())
        #expect(throws: PlanningDraftCodecError.unsupportedVersion(99)) {
            try PlanningDraftCodec.decode(data, version: 99)
        }
    }

    @Test func corruptPayloadLeavesRowUntouched() throws {
        let context = ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
        let bytes = Data([0xFF, 0x00, 0x13])
        let draft = PlanningDraft(payloadData: bytes)
        context.insert(draft)
        try context.save()
        #expect(throws: (any Error).self) { try PlanningDraftCodec.decode(draft) }
        let rows = try context.fetch(FetchDescriptor<PlanningDraft>())
        #expect(rows.count == 1)
        #expect(rows.first?.payloadData == bytes)
        #expect(rows.first?.deletedAt == nil)
    }

    @Test func persistsAcrossReopenAndSkipsSoftDeleted() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("draft-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = fullPlan()
        let id = UUID()
        do {
            let container = try ModelContainer(for: CadenceStore.schema,
                                               configurations: ModelConfiguration(schema: CadenceStore.schema, url: url))
            let context = ModelContext(container)
            context.insert(PlanningDraft(id: id, title: "Push", payloadData: try PlanningDraftCodec.encode(plan),
                                         originDevice: "phone"))
            let gone = PlanningDraft(title: "Old", payloadData: Data(), updatedAt: Date.distantFuture)
            gone.deletedAt = Date()
            context.insert(gone)
            try context.save()
        }
        let container = try ModelContainer(for: CadenceStore.schema,
                                           configurations: ModelConfiguration(schema: CadenceStore.schema, url: url))
        let context = ModelContext(container)
        let current = try #require(PlanningDraft.current(in: context))
        #expect(current.id == id)
        #expect(current.originDevice == "phone")
        #expect(try PlanningDraftCodec.decode(current) == plan)
    }

    @Test func exportMergeRestoresDraft() throws {
        let source = ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
        let plan = fullPlan()
        source.insert(PlanningDraft(title: "Push", payloadData: try PlanningDraftCodec.encode(plan)))
        try source.save()
        let archive = try NativeDatabaseExport.build(from: source)
        let destination = ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
        _ = try NativeDatabaseExport.merge(archive, in: destination)
        let restored = try #require(PlanningDraft.current(in: destination))
        #expect(try PlanningDraftCodec.decode(restored) == plan)
    }

    @Test func registeredInSchemas() {
        #expect(CadenceStore.schema.entities.contains { $0.name == "PlanningDraft" })
        #expect(CadenceStore.syncSchema.entities.contains { $0.name == "PlanningDraft" })
        #expect(!CadenceStore.localSchema.entities.contains { $0.name == "PlanningDraft" })
        #expect(ExportNativeDatabase.entityNames.contains("PlanningDraft"))
    }
}
#endif
