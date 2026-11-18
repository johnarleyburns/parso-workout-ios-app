import Foundation
import Testing
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures
import CadenceCore

struct WatchSingleExerciseSuggestionContextTests {
    private let asOf = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func candidates() -> [SuggestedExerciseCandidate] {
        [SuggestedExerciseCandidate(id: "legacy:bench press", name: "Bench Press", mechanics: .compound,
                                    primaryMuscles: ["chest"], secondaryMuscles: ["triceps"],
                                    equipment: .barbell, trainingTypes: [.strength],
                                    modalities: [], sportContexts: [.generalFitness]),
         SuggestedExerciseCandidate(id: "legacy:squat", name: "Squat", mechanics: .compound,
                                    primaryMuscles: ["quadriceps"], equipment: nil,
                                    isPersonalized: true)]
    }

    private func engine() -> SuggestedWorkoutEngineContext {
        SuggestedWorkoutEngineContext(experience: .intermediate,
                                      schedule: CoachSchedulePreferences(
                                        restPreference: .fixed(days: [.sunday, .wednesday])),
                                      availableEquipment: [.barbell, .dumbbell],
                                      environment: "commercial_gym", asOf: asOf)
    }

    private func direct() -> SuggestedWorkoutInput {
        SuggestedWorkoutInput(completedSetsByMuscle: ["chest": 2], candidates: candidates(),
                              historyWorkoutCount: 5, historyWorkingSetCount: 40,
                              recentlyCompletedCandidateIDs: ["legacy:squat"],
                              trackedGroups: [.chest, .quadriceps],
                              preferredSetsPerExercise: 3, mostRecentExerciseWorkingSets: 4,
                              trainingGoal: .hypertrophy, preferredStyle: .fitness,
                              engineContext: engine())
    }

    private func context() -> WatchSingleExerciseSuggestionContext {
        let d = direct()
        return WatchSingleExerciseSuggestionContext(
            generatedAt: asOf,
            baseInput: .init(completedSetsByMuscle: d.completedSetsByMuscle,
                             candidates: d.candidates.map(WatchSingleExerciseSuggestionContext.Candidate.init),
                             historyWorkoutCount: 5, historyWorkingSetCount: 40,
                             recentlyCompletedCandidateIDs: ["legacy:squat"],
                             trackedGroupIDs: Set(d.trackedGroups.map(\.rawValue)),
                             preferredSetsPerExercise: 3, mostRecentExerciseWorkingSets: 4,
                             trainingGoalRawValue: TrainingGoal.hypertrophy.rawValue,
                             preferredStyleRawValue: SuggestedWorkoutStyle.fitness.rawValue,
                             engineContext: .init(engine())))
    }

    @Test func propertyListAndJSONRoundTrip() throws {
        let ctx = context()
        let plist = try PropertyListEncoder().encode(ctx)
        #expect(try PropertyListDecoder().decode(WatchSingleExerciseSuggestionContext.self, from: plist) == ctx)
        let json = try JSONEncoder().encode(ctx)
        #expect(try JSONDecoder().decode(WatchSingleExerciseSuggestionContext.self, from: json) == ctx)
    }

    @Test func adapterMatchesDirectInputAndPreservesCanonicalIDs() throws {
        let adapted = try #require(context().suggestedWorkoutInput(allocated: [:], excluding: []))
        #expect(adapted == direct())
        #expect(adapted.candidates.map(\.id) == ["legacy:bench press", "legacy:squat"])
        let excluded = try #require(context().suggestedWorkoutInput(allocated: ["chest": 1], excluding: ["legacy:squat"]))
        #expect(excluded.candidates.map(\.id) == ["legacy:bench press"])
        #expect(excluded.completedSetsByMuscle["chest"] == 3)
    }

    @Test func enumConversionRoundTripsEveryCase() {
        for m in Mechanics.allCases { #expect(Mechanics(rawValue: m.rawValue) == m) }
        var c = context()
        c.baseInput.candidates[0].trainingTypeRawValues = ["bogus", ExerciseTrainingType.strength.rawValue]
        let out = c.suggestedWorkoutInput(allocated: [:], excluding: [])
        #expect(out?.candidates.first?.trainingTypes == [.strength])
    }

    @Test func invalidAndFuturePayloadsAreRejected() {
        var future = context(); future.version = WatchSingleExerciseSuggestionContext.currentVersion + 1
        #expect(future.suggestedWorkoutInput(allocated: [:], excluding: []) == nil)
        var zero = context(); zero.version = 0
        #expect(zero.suggestedWorkoutInput(allocated: [:], excluding: []) == nil)
        var goal = context(); goal.baseInput.trainingGoalRawValue = "nope"
        #expect(goal.suggestedWorkoutInput(allocated: [:], excluding: []) == nil)
        var style = context(); style.baseInput.preferredStyleRawValue = "nope"
        #expect(style.suggestedWorkoutInput(allocated: [:], excluding: []) == nil)
        var exp = context(); exp.baseInput.engineContext.experienceRawValue = "nope"
        #expect(exp.suggestedWorkoutInput(allocated: [:], excluding: []) == nil)
        var rest = context(); rest.baseInput.engineContext.schedule.restKind = "nope"
        #expect(rest.suggestedWorkoutInput(allocated: [:], excluding: []) == nil)
        var sets = context(); sets.baseInput.preferredSetsPerExercise = 0
        #expect(sets.suggestedWorkoutInput(allocated: [:], excluding: []) == nil)
        var tracked = context(); tracked.baseInput.trackedGroupIDs = ["unknown"]
        #expect(tracked.suggestedWorkoutInput(allocated: [:], excluding: []) == nil)
        var badDate = context(); badDate.baseInput.engineContext.asOf = Date(timeIntervalSinceReferenceDate: .nan)
        #expect(badDate.suggestedWorkoutInput(allocated: [:], excluding: []) == nil)
    }

    @Test func badCandidateIsDroppedNotInvented() throws {
        var c = context(); c.baseInput.candidates[0].mechanicsRawValue = "nope"
        let out = try #require(c.suggestedWorkoutInput(allocated: [:], excluding: []))
        #expect(out.candidates.map(\.id) == ["legacy:squat"])
    }

    @Test func nonFiniteNumbersAreSanitized() throws {
        var c = context()
        c.baseInput.completedSetsByMuscle = ["chest": .nan, "back": .infinity, "legs": -4, "arms": 2]
        let out = try #require(c.suggestedWorkoutInput(allocated: ["arms": .nan, "chest": 1], excluding: []))
        #expect(out.completedSetsByMuscle == ["legs": 0, "arms": 2, "chest": 1])
    }

    @Test func keyIsDefined() {
        #expect(WatchSync.Key.singleExerciseSuggestionContext == "suggestion.singleExerciseContext")
    }
}
