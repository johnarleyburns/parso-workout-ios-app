import Testing
@testable import CadenceFeatures

@Suite struct WatchTodayRecommendationsTests {
    private typealias S = WatchSync.TodayPlan.Session
    private let s1 = S(id: "s1", kind: .strength, label: "A", exerciseNames: ["Squat"])
    private let s2 = S(id: "s2", kind: .strength, label: "B", exerciseNames: ["Bench"])
    private let c1 = S(id: "c1", kind: .cardio, label: "Run", cardioType: "run", durationMinutes: 30, zone: 2)
    private let r = S(id: "r", kind: .rest, label: "Rest")

    @Test func strengthThenCardioOrderExcludingRest() {
        let rows = WatchTodayRecommendations.rows(for: .init(sessions: [r, c1, s1, s2]))
        #expect(rows.map(\.id) == ["s1", "c1"])
        #expect(rows.map(\.accessibilityIdentifier) ==
                ["watch.todayRecommendation.strength.start", "watch.todayRecommendation.cardio.start"])
        #expect(rows[1].isAlsoPlanned && !rows[0].isAlsoPlanned)
        #expect(rows[1].session.durationMinutes == 30 && rows[1].session.zone == 2)
    }

    @Test func singleRowAndRestOnly() {
        #expect(WatchTodayRecommendations.rows(for: .init(sessions: [c1])).map(\.id) == ["c1"])
        #expect(!WatchTodayRecommendations.rows(for: .init(sessions: [c1]))[0].isAlsoPlanned)
        #expect(WatchTodayRecommendations.rows(for: .init(sessions: [r])).isEmpty)
        #expect(WatchTodayRecommendations.rows(for: nil).isEmpty)
    }

    @Test func actionButtonChoosesWhenTwoAndLaunchesWhenOne() {
        #expect(WatchTodayRecommendations.startDecision(for: .init(sessions: [s1, c1])) == .choose)
        if case .launch(let row) = WatchTodayRecommendations.startDecision(for: .init(sessions: [c1])) {
            #expect(row.id == "c1")
        } else { Issue.record("expected launch") }
        #expect(WatchTodayRecommendations.startDecision(for: .init(sessions: [r])) == .none)
    }

    @Test func resumeOutranksRecommendations() {
        let plan = WatchSync.TodayPlan(sessions: [s1, c1])
        #expect(WatchTodayRecommendations.visibleRows(for: plan, hasResume: true).isEmpty)
        #expect(WatchTodayRecommendations.visibleRows(for: plan, hasResume: false).count == 2)
    }
}
