import Testing
import Foundation
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures
import CadenceCore

@MainActor
final class WatchSuggestedExerciseShellTests {
    private let asOf = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// A realistic, phone-shaped context — same shape
    /// `WatchSingleExerciseSuggestionAssemblerTests` proves `make(...)` accepts.
    /// Field report: tapping "Suggest" never resolved past "Finding an
    /// exercise…". The only existing shell test covered a *missing* context
    /// (`loadContext: { nil }` → `.unavailable`); nothing exercised the happy
    /// path where a real context is present and should resolve.
    private func realisticContext() -> WatchSingleExerciseSuggestionContext {
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
            trackedGroups: [.chest, .quadriceps, .lats], preferredSetsPerExercise: 3,
            trainingGoal: .hypertrophy, engineContext: engine)
        return WatchSingleExerciseSuggestionContext(
            generatedAt: asOf,
            baseInput: .init(completedSetsByMuscle: input.completedSetsByMuscle,
                             candidates: cands.map(WatchSingleExerciseSuggestionContext.Candidate.init),
                             trackedGroupIDs: Set(input.trackedGroups.map(\.rawValue)),
                             preferredSetsPerExercise: 3,
                             trainingGoalRawValue: input.trainingGoal.rawValue,
                             preferredStyleRawValue: input.preferredStyle.rawValue,
                             engineContext: .init(engine)))
    }

    @Test func realisticContextResolvesPastCalculatingInsteadOfHangingForever() async throws {
        // The real generator is CPU-bound and covered by the session tests; the
        // shell only needs to prove it assembles the context and leaves
        // `.calculating`. A deterministic generator keeps this test independent
        // of release-runner thread contention.
        let expected = SuggestedWorkoutExercise(
            candidateID: "legacy:bench press", name: "Bench Press", mechanics: .compound,
            plannedSets: 3, repRange: 8...12, contributions: [], selectionScore: 1)
        let session = WatchSingleExerciseSuggestionSession(generator: { _, _ in expected })
        let shell = WatchSuggestedExerciseShell(
            session: session,
            loadContext: { self.realisticContext() })
        shell.start(activeNames: [], activeWorkingSets: [])
        await shell.session.pendingTask?.value
        #expect(shell.phase == .ready(expected))
    }

    @Test func missingContextIsUnavailableNotARandomFallback() {
        let shell = WatchSuggestedExerciseShell(loadContext: { nil })
        #expect(shell.phase == .calculating)
        shell.start(activeNames: ["Bench Press"], activeWorkingSets: [])
        #expect(shell.phase == .unavailable)
        #expect(shell.session.state == .idle)
    }

    @Test func aGeneratorThatReturnsAnActiveExerciseIsNeverPresentedAsNew() async {
        let duplicate = SuggestedWorkoutExercise(
            candidateID: "legacy:bench press", name: "bench press", mechanics: .compound,
            plannedSets: 3, repRange: 8...12, contributions: [], selectionScore: 1)
        let session = WatchSingleExerciseSuggestionSession(generator: { _, _ in duplicate })
        let shell = WatchSuggestedExerciseShell(
            session: session,
            loadContext: { self.realisticContext() })
        shell.start(activeNames: ["Bench Press"], activeWorkingSets: [])
        await shell.session.pendingTask?.value
        #expect(shell.phase == .noEligibleResult)
    }

    @Test func retryReloadsContextAndStaysUnavailableWhileAbsent() {
        var loads = 0
        let shell = WatchSuggestedExerciseShell(loadContext: { loads += 1; return nil })
        shell.start(activeNames: [], activeWorkingSets: [])
        shell.start(activeNames: [], activeWorkingSets: [])
        #expect(loads == 1)
        shell.retry(activeNames: [], activeWorkingSets: [])
        #expect(loads == 2)
        #expect(shell.phase == .unavailable)
    }

    @Test func copyIsStable() {
        #expect(WatchSuggestedExerciseShell.unavailableMessage ==
                       "Suggestions are updating—sync with iPhone and try again")
        #expect(WatchSuggestedExerciseShell.calculatingTitle == "Finding an exercise…")
    }
}
