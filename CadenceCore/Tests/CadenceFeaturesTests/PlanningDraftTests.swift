import XCTest
import SwiftData
import CadenceCore
@testable import CadenceFeatures

final class PlanningDraftTests: XCTestCase {
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

    func testRoundTripPreservesEveryField() throws {
        let plan = fullPlan()
        let data = try PlanningDraftCodec.encode(plan)
        let decoded = try PlanningDraftCodec.decode(data, version: PlanningDraftPayload.currentVersion)
        XCTAssertEqual(decoded, plan)
        XCTAssertEqual(EditablePlanPayload(decoded), EditablePlanPayload(plan))
    }

    func testUnknownVersionThrows() throws {
        let data = try PlanningDraftCodec.encode(fullPlan())
        XCTAssertThrowsError(try PlanningDraftCodec.decode(data, version: 99)) {
            XCTAssertEqual($0 as? PlanningDraftCodecError, .unsupportedVersion(99))
        }
    }

    func testCorruptPayloadLeavesRowUntouched() throws {
        let context = ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
        let bytes = Data([0xFF, 0x00, 0x13])
        let draft = PlanningDraft(payloadData: bytes)
        context.insert(draft)
        try context.save()
        XCTAssertThrowsError(try PlanningDraftCodec.decode(draft))
        let rows = try context.fetch(FetchDescriptor<PlanningDraft>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.payloadData, bytes)
        XCTAssertNil(rows.first?.deletedAt)
    }

    func testPersistsAcrossReopenAndSkipsSoftDeleted() throws {
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
        let current = try XCTUnwrap(PlanningDraft.current(in: context))
        XCTAssertEqual(current.id, id)
        XCTAssertEqual(current.originDevice, "phone")
        XCTAssertEqual(try PlanningDraftCodec.decode(current), plan)
    }

    func testExportMergeRestoresDraft() throws {
        let source = ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
        let plan = fullPlan()
        source.insert(PlanningDraft(title: "Push", payloadData: try PlanningDraftCodec.encode(plan)))
        try source.save()
        let archive = try NativeDatabaseExport.build(from: source)
        let destination = ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
        _ = try NativeDatabaseExport.merge(archive, in: destination)
        let restored = try XCTUnwrap(PlanningDraft.current(in: destination))
        XCTAssertEqual(try PlanningDraftCodec.decode(restored), plan)
    }

    func testRegisteredInSchemas() {
        XCTAssertTrue(CadenceStore.schema.entities.contains { $0.name == "PlanningDraft" })
        XCTAssertTrue(CadenceStore.syncSchema.entities.contains { $0.name == "PlanningDraft" })
        XCTAssertFalse(CadenceStore.localSchema.entities.contains { $0.name == "PlanningDraft" })
        XCTAssertTrue(ExportNativeDatabase.entityNames.contains("PlanningDraft"))
    }
}
