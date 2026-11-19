import Foundation
import Testing
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures
import CadenceCore

struct WatchSingleExerciseSuggestionAssemblerTests {
    private let asOf = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func context() -> WatchSingleExerciseSuggestionContext {
        let engine = SuggestedWorkoutEngineContext(
            experience: .intermediate,
            schedule: CoachSchedulePreferences(restPreference: .fixed(days: [.sunday])),
            availableEquipment: [.barbell], environment: "commercial_gym", asOf: asOf)
        let cands = [
            SuggestedExerciseCandidate(id: "legacy:bench press", name: "Bench Press", mechanics: .compound,
                                       primaryMuscles: ["chest"], secondaryMuscles: ["triceps"], equipment: .barbell),
            SuggestedExerciseCandidate(id: "legacy:squat", name: "Squat", mechanics: .compound,
                                       primaryMuscles: ["quadriceps"], equipment: .barbell),
            SuggestedExerciseCandidate(id: "legacy:row", name: "Row", mechanics: .compound,
                                       primaryMuscles: ["lats"], equipment: .barbell)]
        let input = SuggestedWorkoutInput(
            completedSetsByMuscle: ["chest": 2], candidates: cands,
            recentlyCompletedCandidateIDs: ["legacy:squat"],
            trackedGroups: [.chest, .quadriceps], preferredSetsPerExercise: 3,
            trainingGoal: .hypertrophy, engineContext: engine)
        return WatchSingleExerciseSuggestionContext(
            generatedAt: asOf,
            baseInput: .init(completedSetsByMuscle: input.completedSetsByMuscle,
                             candidates: cands.map(WatchSingleExerciseSuggestionContext.Candidate.init),
                             recentlyCompletedCandidateIDs: input.recentlyCompletedCandidateIDs,
                             trackedGroupIDs: Set(input.trackedGroups.map(\.rawValue)),
                             preferredSetsPerExercise: 3,
                             trainingGoalRawValue: input.trainingGoal.rawValue,
                             preferredStyleRawValue: input.preferredStyle.rawValue,
                             engineContext: .init(engine)))
    }

    private func sets(_ name: String, _ n: Int, warmups: Int = 0) -> [WatchSuggestionSet] {
        (0..<n).map { _ in WatchSuggestionSet(exerciseName: name) }
            + (0..<warmups).map { _ in WatchSuggestionSet(exerciseName: name, isWarmup: true) }
    }

    @Test func activeBenchIsExcludedAndAllocated() throws {
        let input = try #require(WatchSingleExerciseSuggestionAssembler.make(
            context: context(), activeExerciseNames: ["bench press"],
            activeWorkingSets: sets("Bench Press", 3, warmups: 2),
            transientExcludedCandidateIDs: []))
        #expect(!input.candidates.contains { $0.id == "legacy:bench press" })
        #expect(input.candidates.count == 2)
        // Same math as phone plannedTotals: 3 working sets x direct 1.0 / indirect 0.5; warmups ignored.
        #expect(input.completedSetsByMuscle["chest"] == Double(2 + 3))
        #expect(input.completedSetsByMuscle["triceps"] == 1.5)
        #expect(input.recentlyCompletedCandidateIDs == ["legacy:squat"])
    }

    @Test func transientExclusionRemovesOnlyThatCandidate() throws {
        let input = try #require(WatchSingleExerciseSuggestionAssembler.make(
            context: context(), activeExerciseNames: [], activeWorkingSets: [],
            transientExcludedCandidateIDs: ["legacy:row"]))
        #expect(Set(input.candidates.map(\.id)) == ["legacy:bench press", "legacy:squat"])
    }

    @Test func missingMetadataOmitsAllocationButStillExcludes() throws {
        let input = try #require(WatchSingleExerciseSuggestionAssembler.make(
            context: context(), activeExerciseNames: ["Mystery Lift"],
            activeWorkingSets: sets("Mystery Lift", 4), transientExcludedCandidateIDs: []))
        #expect(input.completedSetsByMuscle == ["chest": 2])
        #expect(input.candidates.count == 3)
    }

    @Test func invalidContextReturnsNil() {
        var bad = context()
        bad.baseInput.trainingGoalRawValue = "bogus"
        #expect(WatchSingleExerciseSuggestionAssembler.make(
            context: bad, activeExerciseNames: [], activeWorkingSets: [],
            transientExcludedCandidateIDs: []) == nil)
    }

    @Test func repeatedAssemblyDoesNotChangeContext() {
        let ctx = context()
        let before = ctx
        for _ in 0..<3 {
            _ = WatchSingleExerciseSuggestionAssembler.make(
                context: ctx, activeExerciseNames: ["Bench Press"],
                activeWorkingSets: sets("Bench Press", 3), transientExcludedCandidateIDs: ["legacy:row"])
        }
        #expect(ctx == before)
    }
}
