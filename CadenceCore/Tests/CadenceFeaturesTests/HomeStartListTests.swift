import Testing
import CadenceCore
import CadenceWorkoutFeatures

struct HomeStartListTests {
    private func titles(_ rows: [HomeStartRow]) -> [String] {
        rows.map {
            switch $0 {
            case .choice(let choice): choice.title
            case .more: "More…"
            }
        }
    }

    @Test func listIsLiftThenThreeRecentCardioThenMore() {
        let rows = HomeStartList.rows(recentCardio: [.run, .cycle, .swim, .hiit])
        #expect(rows.count == 5)
        #expect(titles(rows) == ["Lift", "Run", "Cycle", "Swim", "More…"])
        #expect(rows.first == .choice(.strength(.suggested)))
        #expect(rows.last == .more)
    }

    @Test func recentCardioIsDeduplicatedKeepingTheMostRecentFirst() {
        let rows = HomeStartList.rows(recentCardio: [.run, .run, .cycle, .run, .walk])
        #expect(titles(rows) == ["Lift", "Run", "Cycle", "Walk", "More…"])
    }

    @Test func shortHistoryPadsTheThreeSlotsSoTheListStaysFiveRows() {
        let rows = HomeStartList.rows(recentCardio: [.swim])
        #expect(rows.count == 5)
        #expect(titles(rows).first == "Lift")
        #expect(titles(rows).contains("Swim"))
        #expect(titles(rows).last == "More…")
        #expect(Set(titles(rows)).count == 5)
    }

    @Test func emptyHistoryStillShowsThreeConcreteCardioRows() {
        let rows = HomeStartList.rows(recentCardio: [])
        #expect(rows.count == 5)
        #expect(rows.first == .choice(.strength(.suggested)))
        #expect(rows.last == .more)
    }

    @Test func moreListsEveryCardioChoiceAlphabetically() {
        let more = HomeStartList.moreChoices()
        let cardioCount = HomeWorkoutStartChoice.cardioChoices.count
        #expect(more.count == cardioCount)
        #expect(more.map(\.title) == more.map(\.title).sorted { $0.localizedStandardCompare($1) == .orderedAscending })
        #expect(more.allSatisfy { choice in
            if case .cardio = choice { return true }
            if case .suggestedCardio = choice { return true }
            return false
        })
    }

    @Test func suggestedCardioIsRenamedCardioForYou() {
        #expect(HomeWorkoutStartChoice.suggestedCardio.title == "Cardio for You")
    }

    @Test func cardioTypeMapsBackToWorkoutType() {
        #expect(WorkoutType(cardioType: .run) == .run)
        #expect(WorkoutType(cardioType: .stairClimber) == .stairClimber)
        #expect(WorkoutType(cardioType: .other) == .other)
    }
}
