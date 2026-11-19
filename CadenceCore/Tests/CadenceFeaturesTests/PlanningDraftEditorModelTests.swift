#if canImport(SwiftData)
import Testing
import SwiftData
import CadenceCore
import CadencePhoneFeatures
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

@MainActor
struct PlanningDraftEditorModelTests {
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

    @Test func emptyDraftCannotStartOrSchedule() throws {
        let model = try seeded([], context: try makeContext())
        #expect(model.isEmpty)
        #expect(!model.canStart)
        #expect(!model.needsDiscardConfirmation)
    }

    @Test func removeAndReorderPersistExactOrder() throws {
        let model = try seeded(["A", "B", "C"], context: try makeContext())
        let ids = model.plan.exercises.map(\.id)
        model.moveExercise(id: ids[2], by: -2)
        #expect(model.plan.exercises.map(\.name) == ["C", "A", "B"])
        #expect(!model.canMove(id: ids[2], by: -1))
        model.removeExercise(id: ids[0])
        #expect(try persisted(model).exercises.map(\.name) == ["C", "B"])
        #expect(model.canStart)
    }

    @Test func setEditsPersistAndKeepAtLeastOneSet() throws {
        let model = try seeded(["A"], context: try makeContext())
        let exercise = model.plan.exercises[0]
        model.addSet(to: exercise.id)
        let sets = model.plan.exercises[0].sets
        #expect(sets.count == exercise.sets.count + 1)
        model.setReps(exerciseID: exercise.id, setID: sets[0].id, reps: 5)
        model.setWeight(exerciseID: exercise.id, setID: sets[0].id, weight: 80)
        let stored = try persisted(model).exercises[0].sets[0]
        #expect(stored.targetReps == 5)
        #expect(stored.targetWeight == 80)
        for set in model.plan.exercises[0].sets.dropFirst() {
            model.removeSet(exerciseID: exercise.id, setID: set.id)
        }
        model.removeSet(exerciseID: exercise.id, setID: sets[0].id)
        #expect(try persisted(model).exercises[0].sets.count == 1)
    }

    @Test func titleDebouncedThenFlushed() throws {
        let model = try seeded(["A"], context: try makeContext())
        model.editTitle("Push Day")
        #expect(model.displayTitle == "Push Day")
        #expect(model.draft.title != "Push Day")
        model.flush()
        #expect(model.draft.title == "Push Day")
        #expect(model.pendingTitle == nil)
    }

    @Test func restoreReloadsExactPlan() throws {
        let context = try makeContext()
        let store = PlanningDraftStore()
        let model = try seeded(["A", "B"], store: store, context: context)
        model.editTitle("Legs"); model.flush()
        model.moveExercise(id: model.plan.exercises[1].id, by: -1)
        let reopened = try PlanningDraftEditorModel(drafts: store, context: context)
        #expect(reopened.plan.title == "Legs")
        #expect(reopened.plan.exercises.map(\.name) == ["B", "A"])
    }

    @Test func saveFailureKeepsPlanAndRetrySucceeds() throws {
        let context = try makeContext()
        var fail = false
        let store = PlanningDraftStore(save: { if fail { throw Boom() } else { try $0.save() } })
        let model = try seeded(["A", "B"], store: store, context: context)
        fail = true
        model.removeExercise(id: model.plan.exercises[0].id)
        #expect(model.saveError != nil)
        #expect(model.plan.exercises.count == 2)
        #expect(try persisted(model).exercises.count == 2)
        fail = false
        model.retrySave()
        #expect(model.saveError == nil)
        #expect(try persisted(model).exercises.map(\.name) == ["B"])
    }

    @Test func discardRequiresConfirmationWhenNonEmptyAndSoftDeletes() throws {
        let context = try makeContext()
        let store = PlanningDraftStore()
        let model = try seeded(["A"], store: store, context: context)
        #expect(model.needsDiscardConfirmation)
        #expect(model.discard())
        #expect(model.isDiscarded)
        #expect(!model.canStart)
        #expect(try store.currentDraft(in: context) == nil)
    }
}
#endif
