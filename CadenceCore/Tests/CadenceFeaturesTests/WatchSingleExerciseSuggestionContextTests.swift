import XCTest
@testable import CadenceFeatures
import CadenceCore

final class WatchSingleExerciseSuggestionContextTests: XCTestCase {
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

    func testPropertyListAndJSONRoundTrip() throws {
        let ctx = context()
        let plist = try PropertyListEncoder().encode(ctx)
        XCTAssertEqual(try PropertyListDecoder().decode(WatchSingleExerciseSuggestionContext.self, from: plist), ctx)
        let json = try JSONEncoder().encode(ctx)
        XCTAssertEqual(try JSONDecoder().decode(WatchSingleExerciseSuggestionContext.self, from: json), ctx)
    }

    func testAdapterMatchesDirectInputAndPreservesCanonicalIDs() throws {
        let adapted = try XCTUnwrap(context().suggestedWorkoutInput(allocated: [:], excluding: []))
        XCTAssertEqual(adapted, direct())
        XCTAssertEqual(adapted.candidates.map(\.id), ["legacy:bench press", "legacy:squat"])
        let excluded = try XCTUnwrap(context().suggestedWorkoutInput(allocated: ["chest": 1], excluding: ["legacy:squat"]))
        XCTAssertEqual(excluded.candidates.map(\.id), ["legacy:bench press"])
        XCTAssertEqual(excluded.completedSetsByMuscle["chest"], 3)
    }

    func testEnumConversionRoundTripsEveryCase() {
        for m in Mechanics.allCases { XCTAssertEqual(Mechanics(rawValue: m.rawValue), m) }
        var c = context()
        c.baseInput.candidates[0].trainingTypeRawValues = ["bogus", ExerciseTrainingType.strength.rawValue]
        let out = c.suggestedWorkoutInput(allocated: [:], excluding: [])
        XCTAssertEqual(out?.candidates.first?.trainingTypes, [.strength])
    }

    func testInvalidAndFuturePayloadsAreRejected() {
        var future = context(); future.version = WatchSingleExerciseSuggestionContext.currentVersion + 1
        XCTAssertNil(future.suggestedWorkoutInput(allocated: [:], excluding: []))
        var zero = context(); zero.version = 0
        XCTAssertNil(zero.suggestedWorkoutInput(allocated: [:], excluding: []))
        var goal = context(); goal.baseInput.trainingGoalRawValue = "nope"
        XCTAssertNil(goal.suggestedWorkoutInput(allocated: [:], excluding: []))
        var style = context(); style.baseInput.preferredStyleRawValue = "nope"
        XCTAssertNil(style.suggestedWorkoutInput(allocated: [:], excluding: []))
        var exp = context(); exp.baseInput.engineContext.experienceRawValue = "nope"
        XCTAssertNil(exp.suggestedWorkoutInput(allocated: [:], excluding: []))
        var rest = context(); rest.baseInput.engineContext.schedule.restKind = "nope"
        XCTAssertNil(rest.suggestedWorkoutInput(allocated: [:], excluding: []))
        var sets = context(); sets.baseInput.preferredSetsPerExercise = 0
        XCTAssertNil(sets.suggestedWorkoutInput(allocated: [:], excluding: []))
        var tracked = context(); tracked.baseInput.trackedGroupIDs = ["unknown"]
        XCTAssertNil(tracked.suggestedWorkoutInput(allocated: [:], excluding: []))
        var badDate = context(); badDate.baseInput.engineContext.asOf = Date(timeIntervalSinceReferenceDate: .nan)
        XCTAssertNil(badDate.suggestedWorkoutInput(allocated: [:], excluding: []))
    }

    func testBadCandidateIsDroppedNotInvented() throws {
        var c = context(); c.baseInput.candidates[0].mechanicsRawValue = "nope"
        let out = try XCTUnwrap(c.suggestedWorkoutInput(allocated: [:], excluding: []))
        XCTAssertEqual(out.candidates.map(\.id), ["legacy:squat"])
    }

    func testNonFiniteNumbersAreSanitized() throws {
        var c = context()
        c.baseInput.completedSetsByMuscle = ["chest": .nan, "back": .infinity, "legs": -4, "arms": 2]
        let out = try XCTUnwrap(c.suggestedWorkoutInput(allocated: ["arms": .nan, "chest": 1], excluding: []))
        XCTAssertEqual(out.completedSetsByMuscle, ["legs": 0, "arms": 2, "chest": 1])
    }

    func testKeyIsDefined() {
        XCTAssertEqual(WatchSync.Key.singleExerciseSuggestionContext, "suggestion.singleExerciseContext")
    }
}
