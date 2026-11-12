import XCTest
import SwiftData
@testable import CadenceCore

final class WorkoutSessionAccessorTests: XCTestCase {
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

    func testSetsCountMatchesOrderedSetsCount() throws {
        let ctx = try makeContext()
        let session = WorkoutSession()
        ctx.insert(session)
        let a = exercise("A", ctx)
        for o in [2, 0, 1] { add(o, a, to: session, ctx) }
        XCTAssertEqual(session.setsCount, session.orderedSets.count)
        XCTAssertEqual(session.setsCount, 3)
    }

    func testSetsCountOnEmptySession() throws {
        let ctx = try makeContext()
        let session = WorkoutSession()
        ctx.insert(session)
        XCTAssertEqual(session.setsCount, 0)
        XCTAssertFalse(session.hasSets)
    }

    func testDistinctExerciseCountMatchesExercisesInOrderCount() throws {
        let ctx = try makeContext()
        let session = WorkoutSession()
        ctx.insert(session)
        let a = exercise("A", ctx), b = exercise("B", ctx), c = exercise("C", ctx)
        add(4, c, to: session, ctx); add(0, a, to: session, ctx); add(2, c, to: session, ctx)
        add(1, b, to: session, ctx); add(5, a, to: session, ctx); add(3, c, to: session, ctx)
        XCTAssertEqual(session.distinctExerciseCount, session.exercisesInOrder.count)
        XCTAssertEqual(session.distinctExerciseCount, 3)
    }

    func testDistinctExerciseCountIgnoresSetsWithNoExercise() throws {
        let ctx = try makeContext()
        let session = WorkoutSession()
        ctx.insert(session)
        let a = exercise("A", ctx)
        add(0, a, to: session, ctx)
        add(1, nil, to: session, ctx)
        XCTAssertEqual(session.distinctExerciseCount, 1)
        XCTAssertEqual(session.distinctExerciseCount, session.exercisesInOrder.count)
        XCTAssertEqual(session.setsCount, 2)
    }
}
