import XCTest
import SwiftData
import CadenceCore
@testable import CadenceFeatures

@MainActor
final class TodayQuickRepeatPresenterTests: XCTestCase {
    private func make() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    @discardableResult
    private func session(_ ctx: ModelContext, daysAgo: Int, title: String = "Push Day",
                          withSets: Bool = true) -> WorkoutSession {
        let s = WorkoutSession(date: Date(timeIntervalSince1970: 1_700_000_000 - Double(daysAgo) * 86_400))
        s.title = title
        ctx.insert(s)
        if withSets { ctx.insert(SetEntry(weight: 50, reps: 5, order: 0, session: s)) }
        return s
    }

    func testPresentWhenHistoryExistsAndNothingActive() throws {
        let ctx = try make()
        let recent = session(ctx, daysAgo: 1)
        let display = TodayQuickRepeatPresenter.make(sessions: [recent], hasActiveOrResumableSession: false)
        XCTAssertEqual(display?.sessionID, recent.id)
    }

    func testAbsentWithNoEligibleHistory() throws {
        let ctx = try make()
        XCTAssertNil(TodayQuickRepeatPresenter.make(sessions: [], hasActiveOrResumableSession: false))

        let empty = session(ctx, daysAgo: 1, withSets: false)
        XCTAssertNil(TodayQuickRepeatPresenter.make(sessions: [empty], hasActiveOrResumableSession: false))
    }

    func testAbsentWhenSomethingIsActiveOrResumable() throws {
        let ctx = try make()
        let recent = session(ctx, daysAgo: 1)
        XCTAssertNil(TodayQuickRepeatPresenter.make(sessions: [recent], hasActiveOrResumableSession: true))
    }

    func testTitleFallsBackWhenSessionHasNoTitle() throws {
        let ctx = try make()
        let recent = session(ctx, daysAgo: 1, title: "")
        let display = TodayQuickRepeatPresenter.make(sessions: [recent], hasActiveOrResumableSession: false)
        XCTAssertNotNil(display)
        XCTAssertTrue(display!.title.contains("Workout"))
        XCTAssertFalse(display!.title.contains("—  "))
    }
}
