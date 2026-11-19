#if canImport(SwiftData)
import Foundation
import Testing
import SwiftData
@testable import CadenceCore

@MainActor
struct WorkoutHistoryTests {

    private func makeContext() throws -> ModelContext {
        let container = try CadenceStore.makeModelContainer(inMemory: true)
        return ModelContext(container)
    }

    @Test func emptyStoreReturnsEmpty() throws {
        let ctx = try makeContext()
        #expect(try WorkoutRepository.unifiedHistory(ctx).isEmpty)
    }

    @Test func mergesAndSortsNewestFirst() throws {
        let ctx = try makeContext()

        let oldSession = try WorkoutRepository.createSession(title: "Old", date: Date(timeIntervalSince1970: 1000), in: ctx)
        let newSession = try WorkoutRepository.createSession(title: "New", date: Date(timeIntervalSince1970: 9000), in: ctx)

        // A cardio dated between the two sessions.
        let midCardio = CardioWorkout(type: .walk, start: Date(timeIntervalSince1970: 5000),
                                      end: Date(timeIntervalSince1970: 5600), distance: 1000)
        ctx.insert(midCardio)
        try ctx.save()

        let history = try WorkoutRepository.unifiedHistory(ctx)
        #expect(history.count == 3)
        #expect(history.map(\.id) == [newSession.id, midCardio.id, oldSession.id])
        #expect(history.map(\.date) == [
            Date(timeIntervalSince1970: 9000),
            Date(timeIntervalSince1970: 5000),
            Date(timeIntervalSince1970: 1000),
        ])
    }

    @Test func entryIdentityAndDate() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(title: "S", date: Date(timeIntervalSince1970: 1000), in: ctx)
        let cardio = CardioWorkout(type: .run, start: Date(timeIntervalSince1970: 2000),
                                   end: Date(timeIntervalSince1970: 2600))
        ctx.insert(cardio)
        try ctx.save()

        let history = try WorkoutRepository.unifiedHistory(ctx)
        // Newest first: cardio (2000) then session (1000).
        if case .cardio(let c) = history[0] {
            #expect(c.id == cardio.id)
            #expect(history[0].date == cardio.start)
        } else {
            Issue.record("Expected cardio first")
        }
        if case .strength(let s) = history[1] {
            #expect(s.id == session.id)
            #expect(history[1].date == session.date)
        } else {
            Issue.record("Expected strength second")
        }
    }
}
#endif
