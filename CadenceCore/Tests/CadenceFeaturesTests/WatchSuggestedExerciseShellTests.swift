import Testing
import Foundation
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures
import CadenceCore

@MainActor
@Suite final class WatchSuggestedExerciseShellTests {
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
        let shell = WatchSuggestedExerciseShell(loadContext: { self.realisticContext() })
        shell.start(activeNames: [], activeWorkingSets: [])
        await shell.session.pendingTask?.value
        switch shell.phase {
        case .ready, .noEligibleResult:
            break // resolved — the stuck-forever symptom did not reproduce.
        case .calculating:
            Issue.record("shell is still \"Finding an exercise…\" after the task finished")
        case .unavailable:
            Issue.record("a present, valid context was treated as missing")
        }
    }

    @Test func missingContextIsUnavailableNotARandomFallback() {
        let shell = WatchSuggestedExerciseShell(loadContext: { nil })
        #expect(shell.phase == .calculating)
        shell.start(activeNames: ["Bench Press"], activeWorkingSets: [])
        #expect(shell.phase == .unavailable)
        #expect(shell.session.state == .idle)
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
