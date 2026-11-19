#if canImport(SwiftData)
import Testing
import SwiftData
@testable import CadenceCore

struct WorkoutSessionAccessorTests {
    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    private func exercise(_ name: String, _ ctx: ModelContext) -> Exercise {
        let e = Exercise(name: name)
        ctx.insert(e)
        return e
    }

    private func add(_ order: Int, _ ex: Exercise?, to session: WorkoutSession, _ ctx: ModelContext) {
        let s = SetEntry(weight: 50, reps: 5, order: order, session: session, exercise: ex)
        ctx.insert(s)
    }

    @Test func setsCountMatchesOrderedSetsCount() throws {
        let ctx = try makeContext()
        let session = WorkoutSession()
        ctx.insert(session)
        let a = exercise("A", ctx)
        for o in [2, 0, 1] { add(o, a, to: session, ctx) }
        #expect(session.setsCount == session.orderedSets.count)
        #expect(session.setsCount == 3)
    }

    @Test func setsCountOnEmptySession() throws {
        let ctx = try makeContext()
        let session = WorkoutSession()
        ctx.insert(session)
        #expect(session.setsCount == 0)
        #expect(!session.hasSets)
    }

    @Test func distinctExerciseCountMatchesExercisesInOrderCount() throws {
        let ctx = try makeContext()
        let session = WorkoutSession()
        ctx.insert(session)
        let a = exercise("A", ctx), b = exercise("B", ctx), c = exercise("C", ctx)
        add(4, c, to: session, ctx); add(0, a, to: session, ctx); add(2, c, to: session, ctx)
        add(1, b, to: session, ctx); add(5, a, to: session, ctx); add(3, c, to: session, ctx)
        #expect(session.distinctExerciseCount == session.exercisesInOrder.count)
        #expect(session.distinctExerciseCount == 3)
    }

    @Test func distinctExerciseCountIgnoresSetsWithNoExercise() throws {
        let ctx = try makeContext()
        let session = WorkoutSession()
        ctx.insert(session)
        let a = exercise("A", ctx)
        add(0, a, to: session, ctx)
        add(1, nil, to: session, ctx)
        #expect(session.distinctExerciseCount == 1)
        #expect(session.distinctExerciseCount == session.exercisesInOrder.count)
        #expect(session.setsCount == 2)
    }

    @Test func distinctExercisesInOrderMatchesExercisesInOrderProperty() throws {
        let ctx = try makeContext()
        let session = WorkoutSession()
        ctx.insert(session)
        let a = exercise("A", ctx), b = exercise("B", ctx), c = exercise("C", ctx)
        add(3, a, to: session, ctx); add(1, b, to: session, ctx)
        add(0, a, to: session, ctx); add(2, c, to: session, ctx)
        #expect(WorkoutSession.distinctExercises(inOrder: session.orderedSets) ==
                       session.exercisesInOrder)
    }

    @Test func distinctExercisesStaticHelperWithEmptyInput() {
        #expect(WorkoutSession.distinctExercises(inOrder: []) == [])
    }

    @Test func distinctExercisesStaticHelperPreservesFirstAppearanceOrder() throws {
        let ctx = try makeContext()
        let session = WorkoutSession()
        ctx.insert(session)
        let a = exercise("A", ctx), b = exercise("B", ctx), c = exercise("C", ctx)
        for (o, e) in [b, a, b, c, a].enumerated() { add(o, e, to: session, ctx) }
        #expect(WorkoutSession.distinctExercises(inOrder: session.orderedSets).map(\.name) ==
                       ["B", "A", "C"])
    }
}
#endif
