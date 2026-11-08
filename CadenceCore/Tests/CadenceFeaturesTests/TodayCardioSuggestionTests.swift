import XCTest
import CadenceCore
@testable import CadenceFeatures

final class TodayCardioSuggestionTests: XCTestCase {
    private func make(_ minutes: Int) -> CardioSuggestion {
        CardioSuggestion(type: .run, durationMinutes: minutes, intensity: .easy,
                         rationale: "r", citationIDs: [])
    }

    func testGateAppliesFirstAndIdenticalHoldsDifferent() {
        XCTAssertEqual(TodayCardioReplacementGate.decide(displayed: nil, fresh: make(20)), .applyImmediately)
        XCTAssertEqual(TodayCardioReplacementGate.decide(displayed: make(20), fresh: make(20)), .applyImmediately)
        XCTAssertEqual(TodayCardioReplacementGate.decide(displayed: make(20), fresh: make(30)), .holdPending)
    }

    func testCacheIsSameDayOnly() {
        let defaults = UserDefaults(suiteName: "TodayCardioSuggestionTests")!
        defaults.removePersistentDomain(forName: "TodayCardioSuggestionTests")
        let now = Date()
        TodayCardioSuggestionCache().save(make(25), now: now, defaults: defaults)
        XCTAssertEqual(TodayCardioSuggestionCache().load(now: now, defaults: defaults), make(25))
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now)!
        XCTAssertNil(TodayCardioSuggestionCache().load(now: tomorrow, defaults: defaults))
    }

    func testTwoADaysIsAlwaysOn() throws {
        XCTAssertTrue(CoachSchedulePreferences(allowsTwoADays: false).allowsTwoADays)
        XCTAssertTrue(CoachSchedulePreferences.default.withTwoADays(false).allowsTwoADays)
        let legacy = Data(#"{"allowsTwoADays":false}"#.utf8)
        XCTAssertTrue(try JSONDecoder().decode(CoachSchedulePreferences.self, from: legacy).allowsTwoADays)
    }
}

final class SuggestAnotherInputTests: XCTestCase {
    func testExcludingCandidatesRemovesNamedAndKeepsFallback() {
        func cand(_ id: String) -> SuggestedExerciseCandidate {
            SuggestedExerciseCandidate(id: id, name: id, mechanics: .compound, primaryMuscles: ["chest"],
                                       secondaryMuscles: [], equipment: nil, volumeEligible: true)
        }
        let input = SuggestedWorkoutInput(completedSetsByMuscle: [:], candidates: [cand("A"), cand("B")],
                                          preferredSetsPerExercise: 3, trainingGoal: .strength)
        XCTAssertEqual(input.excludingCandidates(named: ["a"]).candidates.map(\.id), ["B"])
        XCTAssertEqual(input.excludingCandidates(named: ["A", "B"]).candidates.count, 2)
    }
}
