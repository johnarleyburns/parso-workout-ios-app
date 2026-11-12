import XCTest
import SwiftData
import CadenceCore
@testable import CadenceFeatures

@MainActor
final class PreviousWorkoutPickerPolicyTests: XCTestCase {
    private func make() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    @discardableResult
    private func session(_ ctx: ModelContext, daysAgo: Int, withSets: Bool = true) -> WorkoutSession {
        let s = WorkoutSession(date: Date(timeIntervalSince1970: 1_700_000_000 - Double(daysAgo) * 86_400))
        ctx.insert(s)
        if withSets { ctx.insert(SetEntry(weight: 50, reps: 5, order: 0, session: s)) }
        return s
    }

    func testCandidatesExcludeTheCurrentSession() throws {
        let ctx = try make()
        let current = session(ctx, daysAgo: 0)
        let others = (1...3).map { session(ctx, daysAgo: $0) }
        let result = PreviousWorkoutPickerPolicy.candidates(sessions: [current] + others, excluding: current)
        XCTAssertFalse(result.contains { $0.id == current.id })
        XCTAssertEqual(result.count, 3)
    }

    func testCandidatesExcludeSessionsWithNoSets() throws {
        let ctx = try make()
        let current = session(ctx, daysAgo: 0)
        let empty = session(ctx, daysAgo: 1, withSets: false)
        let full = session(ctx, daysAgo: 2)
        let result = PreviousWorkoutPickerPolicy.candidates(sessions: [empty, full], excluding: current)
        XCTAssertEqual(result.map(\.id), [full.id])
    }

    func testCandidatesAreCappedAtTheDocumentedLimit() throws {
        let ctx = try make()
        let current = session(ctx, daysAgo: 0)
        let all = (1...(PreviousWorkoutPickerPolicy.limit + 15)).map { session(ctx, daysAgo: $0) }
        let result = PreviousWorkoutPickerPolicy.candidates(sessions: all, excluding: current)
        XCTAssertEqual(result.count, PreviousWorkoutPickerPolicy.limit)
    }

    func testCandidatesAreNewestFirst() throws {
        let ctx = try make()
        let current = session(ctx, daysAgo: 0)
        let all = [5, 40, 1, 30, 2].map { session(ctx, daysAgo: $0) }
        let result = PreviousWorkoutPickerPolicy.candidates(sessions: all, excluding: current)
        XCTAssertEqual(result.map(\.date), result.map(\.date).sorted(by: >))
        XCTAssertEqual(result.first?.id, all[2].id)
    }
}
