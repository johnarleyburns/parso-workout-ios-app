#if canImport(SwiftData)
import Foundation
import Testing
import SwiftData
import CadenceCore
import CadencePhoneFeatures
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

@MainActor
struct TodayQuickRepeatPresenterTests {
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

    @Test func presentWhenHistoryExistsAndNothingActive() throws {
        let ctx = try make()
        let recent = session(ctx, daysAgo: 1)
        let display = TodayQuickRepeatPresenter.make(sessions: [recent], hasActiveOrResumableSession: false)
        #expect(display?.sessionID == recent.id)
    }

    @Test func absentWithNoEligibleHistory() throws {
        let ctx = try make()
        #expect(TodayQuickRepeatPresenter.make(sessions: [], hasActiveOrResumableSession: false) == nil)

        let empty = session(ctx, daysAgo: 1, withSets: false)
        #expect(TodayQuickRepeatPresenter.make(sessions: [empty], hasActiveOrResumableSession: false) == nil)
    }

    @Test func absentWhenSomethingIsActiveOrResumable() throws {
        let ctx = try make()
        let recent = session(ctx, daysAgo: 1)
        #expect(TodayQuickRepeatPresenter.make(sessions: [recent], hasActiveOrResumableSession: true) == nil)
    }

    @Test func titleFallsBackWhenSessionHasNoTitle() throws {
        let ctx = try make()
        let recent = session(ctx, daysAgo: 1, title: "")
        let display = TodayQuickRepeatPresenter.make(sessions: [recent], hasActiveOrResumableSession: false)
        #expect(display != nil)
        #expect(display!.title.contains("Workout"))
        #expect(!display!.title.contains("—  "))
    }
}
#endif
