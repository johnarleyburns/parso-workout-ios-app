import XCTest
import SwiftData
import CadenceCore
@testable import CadenceFeatures

@MainActor
final class PlanningDraftEditorModelTests: XCTestCase {
    private struct Boom: Error {}

    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    private func seeded(_ names: [String], store: PlanningDraftStore = PlanningDraftStore(),
                        context: ModelContext) throws -> PlanningDraftEditorModel {
        var draft: PlanningDraft?
        for name in names { draft = try store.add(Exercise(name: name), to: draft?.id, in: context) }
        return try PlanningDraftEditorModel(drafts: store, context: context, debounce: .milliseconds(10))
    }

    private func persisted(_ model: PlanningDraftEditorModel) throws -> EditablePlan {
        try PlanningDraftCodec.decode(model.draft)
    }

    func testEmptyDraftCannotStartOrSchedule() throws {
        let model = try seeded([], context: try makeContext())
        XCTAssertTrue(model.isEmpty)
        XCTAssertFalse(model.canStartOrSchedule)
        XCTAssertFalse(model.needsDiscardConfirmation)
    }

    func testRemoveAndReorderPersistExactOrder() throws {
        let model = try seeded(["A", "B", "C"], context: try makeContext())
        let ids = model.plan.exercises.map(\.id)
        model.moveExercise(id: ids[2], by: -2)
        XCTAssertEqual(model.plan.exercises.map(\.name), ["C", "A", "B"])
        XCTAssertFalse(model.canMove(id: ids[2], by: -1))
        model.removeExercise(id: ids[0])
        XCTAssertEqual(try persisted(model).exercises.map(\.name), ["C", "B"])
        XCTAssertTrue(model.canStartOrSchedule)
    }

    func testSetEditsPersistAndKeepAtLeastOneSet() throws {
        let model = try seeded(["A"], context: try makeContext())
        let exercise = model.plan.exercises[0]
        model.addSet(to: exercise.id)
        let sets = model.plan.exercises[0].sets
        XCTAssertEqual(sets.count, exercise.sets.count + 1)
        model.setReps(exerciseID: exercise.id, setID: sets[0].id, reps: 5)
        model.setWeight(exerciseID: exercise.id, setID: sets[0].id, weight: 80)
        let stored = try persisted(model).exercises[0].sets[0]
        XCTAssertEqual(stored.targetReps, 5)
        XCTAssertEqual(stored.targetWeight, 80)
        for set in model.plan.exercises[0].sets.dropFirst() {
            model.removeSet(exerciseID: exercise.id, setID: set.id)
        }
        model.removeSet(exerciseID: exercise.id, setID: sets[0].id)
        XCTAssertEqual(try persisted(model).exercises[0].sets.count, 1)
    }

    func testTitleDebouncedThenFlushed() throws {
        let model = try seeded(["A"], context: try makeContext())
        model.editTitle("Push Day")
        XCTAssertEqual(model.displayTitle, "Push Day")
        XCTAssertNotEqual(model.draft.title, "Push Day")
        model.flush()
        XCTAssertEqual(model.draft.title, "Push Day")
        XCTAssertNil(model.pendingTitle)
    }

    func testRestoreReloadsExactPlan() throws {
        let context = try makeContext()
        let store = PlanningDraftStore()
        let model = try seeded(["A", "B"], store: store, context: context)
        model.editTitle("Legs"); model.flush()
        model.moveExercise(id: model.plan.exercises[1].id, by: -1)
        let reopened = try PlanningDraftEditorModel(drafts: store, context: context)
        XCTAssertEqual(reopened.plan.title, "Legs")
        XCTAssertEqual(reopened.plan.exercises.map(\.name), ["B", "A"])
    }

    func testSaveFailureKeepsPlanAndRetrySucceeds() throws {
        let context = try makeContext()
        var fail = false
        let store = PlanningDraftStore(save: { if fail { throw Boom() } else { try $0.save() } })
        let model = try seeded(["A", "B"], store: store, context: context)
        fail = true
        model.removeExercise(id: model.plan.exercises[0].id)
        XCTAssertNotNil(model.saveError)
        XCTAssertEqual(model.plan.exercises.count, 2)
        XCTAssertEqual(try persisted(model).exercises.count, 2)
        fail = false
        model.retrySave()
        XCTAssertNil(model.saveError)
        XCTAssertEqual(try persisted(model).exercises.map(\.name), ["B"])
    }

    func testDiscardRequiresConfirmationWhenNonEmptyAndSoftDeletes() throws {
        let context = try makeContext()
        let store = PlanningDraftStore()
        let model = try seeded(["A"], store: store, context: context)
        XCTAssertTrue(model.needsDiscardConfirmation)
        XCTAssertTrue(model.discard())
        XCTAssertTrue(model.isDiscarded)
        XCTAssertFalse(model.canStartOrSchedule)
        XCTAssertNil(try store.currentDraft(in: context))
    }
}
