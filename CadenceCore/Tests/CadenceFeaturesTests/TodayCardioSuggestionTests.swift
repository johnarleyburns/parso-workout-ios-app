import Foundation
import Testing
import CadenceCore
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures
import CadencePhoneFeatures

struct TodayCardioSuggestionTests {
    private func make(_ minutes: Int) -> CardioSuggestion {
        CardioSuggestion(type: .run, durationMinutes: minutes, intensity: .easy,
                         rationale: "r", citationIDs: [])
    }

    @Test func gateAppliesFirstAndIdenticalHoldsDifferent() {
        #expect(TodayCardioReplacementGate.decide(displayed: nil, fresh: make(20)) == .applyImmediately)
        #expect(TodayCardioReplacementGate.decide(displayed: make(20), fresh: make(20)) == .applyImmediately)
        #expect(TodayCardioReplacementGate.decide(displayed: make(20), fresh: make(30)) == .holdPending)
    }

    @Test func cacheIsSameDayOnly() {
        let defaults = UserDefaults(suiteName: "TodayCardioSuggestionTests")!
        defaults.removePersistentDomain(forName: "TodayCardioSuggestionTests")
        let now = Date()
        TodayCardioSuggestionCache().save(make(25), now: now, defaults: defaults)
        #expect(TodayCardioSuggestionCache().load(now: now, defaults: defaults) == make(25))
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now)!
        #expect(TodayCardioSuggestionCache().load(now: tomorrow, defaults: defaults) == nil)
    }

    @Test func twoADaysIsAlwaysOn() throws {
        #expect(CoachSchedulePreferences(allowsTwoADays: false).allowsTwoADays)
        #expect(CoachSchedulePreferences.default.withTwoADays(false).allowsTwoADays)
        let legacy = Data(#"{"allowsTwoADays":false}"#.utf8)
        #expect(try JSONDecoder().decode(CoachSchedulePreferences.self, from: legacy).allowsTwoADays)
    }
}

struct SuggestAnotherInputTests {
    @Test func excludingCandidatesRemovesNamedAndKeepsFallback() {
        func cand(_ id: String) -> SuggestedExerciseCandidate {
            SuggestedExerciseCandidate(id: id, name: id, mechanics: .compound, primaryMuscles: ["chest"],
                                       secondaryMuscles: [], equipment: nil, volumeEligible: true)
        }
        let input = SuggestedWorkoutInput(completedSetsByMuscle: [:], candidates: [cand("A"), cand("B")],
                                          preferredSetsPerExercise: 3, trainingGoal: .strength)
        #expect(input.excludingCandidates(named: ["a"]).candidates.map(\.id) == ["B"])
        #expect(input.excludingCandidates(named: ["A", "B"]).candidates.count == 2)
    }
}
