#if canImport(SwiftData)
import Foundation
import Testing
import SwiftData
import CadenceCore
import CadencePhoneFeatures
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

@MainActor
struct PreviousWorkoutPickerPolicyTests {
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

    @Test func candidatesExcludeTheCurrentSession() throws {
        let ctx = try make()
        let current = session(ctx, daysAgo: 0)
        let others = (1...3).map { session(ctx, daysAgo: $0) }
        let result = PreviousWorkoutPickerPolicy.candidates(sessions: [current] + others, excluding: current)
        #expect(!result.contains { $0.id == current.id })
        #expect(result.count == 3)
    }

    @Test func candidatesExcludeSessionsWithNoSets() throws {
        let ctx = try make()
        let current = session(ctx, daysAgo: 0)
        let empty = session(ctx, daysAgo: 1, withSets: false)
        let full = session(ctx, daysAgo: 2)
        let result = PreviousWorkoutPickerPolicy.candidates(sessions: [empty, full], excluding: current)
        #expect(result.map(\.id) == [full.id])
    }

    @Test func candidatesAreCappedAtTheDocumentedLimit() throws {
        let ctx = try make()
        let current = session(ctx, daysAgo: 0)
        let all = (1...(PreviousWorkoutPickerPolicy.limit + 15)).map { session(ctx, daysAgo: $0) }
        let result = PreviousWorkoutPickerPolicy.candidates(sessions: all, excluding: current)
        #expect(result.count == PreviousWorkoutPickerPolicy.limit)
    }

    @Test func candidatesAreNewestFirst() throws {
        let ctx = try make()
        let current = session(ctx, daysAgo: 0)
        let all = [5, 40, 1, 30, 2].map { session(ctx, daysAgo: $0) }
        let result = PreviousWorkoutPickerPolicy.candidates(sessions: all, excluding: current)
        #expect(result.map(\.date) == result.map(\.date).sorted(by: >))
        #expect(result.first?.id == all[2].id)
    }

    @Test func candidatesWithNoExclusionReturnsMostRecentFirst() throws {
        let ctx = try make()
        let old = session(ctx, daysAgo: 5)
        let empty = session(ctx, daysAgo: 2, withSets: false)
        let recent = session(ctx, daysAgo: 1)
        let result = PreviousWorkoutPickerPolicy.candidates(sessions: [old, empty, recent])
        #expect(result.map(\.id) == [recent.id, old.id])
    }
}
#endif
