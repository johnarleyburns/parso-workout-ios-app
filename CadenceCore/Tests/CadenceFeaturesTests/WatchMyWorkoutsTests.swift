import Foundation
import Testing
@testable import CadenceFeatures

struct WatchMyWorkoutsTests {
    @Test func plannedFirstThenNewestHistoryAndSkipsRest() {
        let plan = WatchSync.TodayPlan(sessions: [
            .init(id: "a", kind: .strength, label: "Push", exerciseNames: ["Bench"]),
            .init(id: "b", kind: .rest, label: "Rest"),
        ])
        let old = WatchMyWorkouts.HistoryInput(id: UUID(), title: "Old", date: Date(timeIntervalSince1970: 1), setCount: 3)
        let new = WatchMyWorkouts.HistoryInput(id: UUID(), title: "", date: Date(timeIntervalSince1970: 9), setCount: 5)
        let rows = WatchMyWorkouts.rows(plan: plan, history: [old, new])
        #expect(rows.map(\.status) == [.planned, .completed, .completed])
        #expect(rows[0].title == "Push")
        #expect(rows[1].title == "Workout")
        #expect(rows[2].title == "Old")
    }

    @Test func historyLimitApplies() {
        let h = (0..<5).map { WatchMyWorkouts.HistoryInput(id: UUID(), title: "W", date: Date(timeIntervalSince1970: Double($0)), setCount: 1) }
        #expect(WatchMyWorkouts.rows(plan: nil, history: h, historyLimit: 2).count == 2)
    }
}
