import XCTest
import SwiftData
@testable import CadenceCore

@MainActor
final class WorkoutHistoryTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let container = try CadenceStore.makeModelContainer(inMemory: true)
        return ModelContext(container)
    }

    func testEmptyStoreReturnsEmpty() throws {
        let ctx = try makeContext()
        XCTAssertTrue(try WorkoutRepository.unifiedHistory(ctx).isEmpty)
    }

    func testMergesAndSortsNewestFirst() throws {
        let ctx = try makeContext()

        let oldSession = try WorkoutRepository.createSession(title: "Old", date: Date(timeIntervalSince1970: 1000), in: ctx)
        let newSession = try WorkoutRepository.createSession(title: "New", date: Date(timeIntervalSince1970: 9000), in: ctx)

        // A cardio dated between the two sessions.
        let midCardio = CardioWorkout(type: .walk, start: Date(timeIntervalSince1970: 5000),
                                      end: Date(timeIntervalSince1970: 5600), distance: 1000)
        ctx.insert(midCardio)
        try ctx.save()

        let history = try WorkoutRepository.unifiedHistory(ctx)
        XCTAssertEqual(history.count, 3)
        XCTAssertEqual(history.map(\.id), [newSession.id, midCardio.id, oldSession.id])
        XCTAssertEqual(history.map(\.date), [
            Date(timeIntervalSince1970: 9000),
            Date(timeIntervalSince1970: 5000),
            Date(timeIntervalSince1970: 1000),
        ])
    }

    func testEntryIdentityAndDate() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(title: "S", date: Date(timeIntervalSince1970: 1000), in: ctx)
        let cardio = CardioWorkout(type: .run, start: Date(timeIntervalSince1970: 2000),
                                   end: Date(timeIntervalSince1970: 2600))
        ctx.insert(cardio)
        try ctx.save()

        let history = try WorkoutRepository.unifiedHistory(ctx)
        // Newest first: cardio (2000) then session (1000).
        if case .cardio(let c) = history[0] {
            XCTAssertEqual(c.id, cardio.id)
            XCTAssertEqual(history[0].date, cardio.start)
        } else {
            XCTFail("Expected cardio first")
        }
        if case .strength(let s) = history[1] {
            XCTAssertEqual(s.id, session.id)
            XCTAssertEqual(history[1].date, session.date)
        } else {
            XCTFail("Expected strength second")
        }
    }
}
