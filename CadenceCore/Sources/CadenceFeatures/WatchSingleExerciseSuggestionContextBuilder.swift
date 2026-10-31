import Foundation
import SwiftData
import CadenceCore

/// Builds the phone-side `WatchSingleExerciseSuggestionContext` from the same
/// inputs as `SuggestedExerciseRequestFactory.make` (intentional differences: none
/// beyond the bounds and ordering below). Pure read: no WatchConnectivity, no
/// writes. Callers must pass a `ModelContext` owned by the calling task (never
/// share the main-actor context across actors).
///
/// Bounds and ordering (deterministic for identical store + settings + `now`):
/// - History: sessions with `countsAsStrengthHistory`, newest first (date desc,
///   then id). `historyWorkoutCount` / `historyWorkingSetCount` and the weekly
///   volume use the complete history; `historyData` and the recent-exercise
///   signals use only the newest `maxHistorySessions`.
/// - Candidates: personalized first, then id ascending, truncated to
///   `maxCandidates`. Candidates are NOT filtered by permanent exclusions, so the
///   Watch adapter removes them via `baseInput.permanentlyExcludedCandidateIDs`.
/// - The active workout's exercises/allocation are Watch-local and not included.
public enum WatchSingleExerciseSuggestionContextBuilder {
    public static let maxHistorySessions = 21
    public static let maxCandidates = 900

    public static func make(context: ModelContext,
                            settings: AppSettings,
                            now: Date = .now,
                            historyIndexStorageURL: URL? = ExerciseHistoryIndexStore.defaultStorageURL()
    ) throws -> WatchSingleExerciseSuggestionContext {
        let history = try WorkoutRepository.allSessions(context)
            .filter { $0.countsAsStrengthHistory }
            .sorted { ($0.date, $0.id.uuidString) > ($1.date, $1.id.uuidString) }
        let recent = Array(history.prefix(maxHistorySessions))
        let historyWorkingSetCount = history.reduce(0) { $0 + $1.completedOwnerWorkingSetCount }
        let historyWorkoutCount = history.filter { $0.completedOwnerWorkingSetCount > 0 }.count
        let historyKeys = try ExerciseHistoryIndexStore.personalizedExerciseKeys(
            sessions: history, storageURL: historyIndexStorageURL)
        let exercises = try WorkoutRepository.allExercises(context)
        let schedule = settings.coachSchedulePreferences
        let trackedIDs = Set(schedule.trackedMuscleGroups.map(\.rawValue))
        let persisted = exercises.map { exercise in
            let id = ExerciseSuggestionExclusionKey.forExercise(exercise)
            return SuggestedExerciseCandidate(
                id: id, name: exercise.name,
                mechanics: exercise.mechanicsValue ?? .compound,
                primaryMuscles: exercise.primaryMuscles,
                secondaryMuscles: exercise.secondaryMuscles,
                equipment: exercise.equipmentValue,
                volumeEligible: exercise.volumeEligible,
                trainingTypes: exercise.trainingTypes,
                modalities: exercise.modalities,
                sportContexts: exercise.sportContexts,
                isPersonalized: historyKeys.contains(id))
        }
        let usable = persisted.contains { candidate in
            candidate.volumeEligible && (candidate.primaryMuscles + candidate.secondaryMuscles).contains { muscle in
                guard let group = MuscleGroup.canonical(muscle) else { return false }
                return trackedIDs.isEmpty || trackedIDs.contains(group.rawValue)
            }
        }
        let pool: [SuggestedExerciseCandidate]
        if usable {
            pool = persisted
        } else {
            let starter = ExerciseLibrary.starter.map { template -> SuggestedExerciseCandidate in
                let c = SuggestedExerciseCandidate(template: template)
                return SuggestedExerciseCandidate(
                    id: c.id, name: c.name, mechanics: c.mechanics,
                    primaryMuscles: c.primaryMuscles, secondaryMuscles: c.secondaryMuscles,
                    equipment: c.equipment, volumeEligible: c.volumeEligible,
                    trainingTypes: c.trainingTypes, modalities: c.modalities,
                    sportContexts: c.sportContexts, isPersonalized: historyKeys.contains(c.id))
            }
            pool = starter + persisted.filter(\.isPersonalized)
        }
        var seen = Set<String>()
        let candidates = Array(pool
            .filter { seen.insert($0.id).inserted }
            .sorted { a, b in
                if a.isPersonalized != b.isPersonalized { return a.isPersonalized }
                return a.id < b.id
            }
            .prefix(maxCandidates))

        let facts = TrainingFacts.make(sessions: history, now: now,
                                       goal: settings.trainingGoal,
                                       experience: settings.experienceLevel)
        let historyData = historyWorkingSetCount > 0
            ? TrainingEngineBridge.historyData(from: recent, subjectId: "cladiron-local")
            : nil
        let snapshots = recent.filter { $0.completedOwnerWorkingSetCount > 0 }.map { session in
            RecentCompletedWorkoutSnapshot(
                startedAt: session.date, endedAt: session.endedAt,
                exerciseNames: session.orderedSets.filter { !$0.isWarmup && $0.isOwnerSet && $0.reps > 0 }
                    .compactMap { $0.exercise?.name })
        }
        let exclusionKeys = try ExerciseSuggestionExclusionStore.activeKeys(in: context)
        let excludedIDs = Set(candidates.map(\.id).filter { id in
            exclusionKeys.contains { ExerciseSuggestionExclusionKey.matches($0, candidateID: id) }
        })
        let engine = SuggestedWorkoutEngineContext(
            experience: settings.experienceLevel, schedule: schedule,
            availableEquipment: Equipment.allCases, environment: "commercial_gym", asOf: now)
        return WatchSingleExerciseSuggestionContext(
            generatedAt: now,
            baseInput: .init(
                completedSetsByMuscle: facts.weeklySetsByMuscle,
                candidates: candidates.map(WatchSingleExerciseSuggestionContext.Candidate.init),
                historyData: historyData,
                historyWorkoutCount: historyWorkoutCount,
                historyWorkingSetCount: historyWorkingSetCount,
                recentlyCompletedCandidateIDs: RecentSuggestionExclusion.candidateIDs(
                    from: snapshots, candidates: candidates),
                trackedGroupIDs: Set(schedule.trackedMuscleGroups.map(\.rawValue)),
                preferredSetsPerExercise: schedule.desiredSetsPerExercise,
                mostRecentExerciseWorkingSets: RecentSuggestionExclusion.mostRecentExerciseSetCount(
                    from: snapshots),
                trainingGoalRawValue: settings.trainingGoal.rawValue,
                preferredStyleRawValue: settings.preferredWorkoutStyle.rawValue,
                engineContext: .init(engine),
                permanentlyExcludedCandidateIDs: excludedIDs))
    }

    /// Candidate IDs hidden by active permanent exclusions, using the same
    /// matching as `SuggestedExerciseFilter.excluding` (alias-aware).
    public static func permanentlyExcludedCandidateIDs(
        in snapshot: WatchSingleExerciseSuggestionContext, context: ModelContext
    ) throws -> Set<String> {
        let keys = try ExerciseSuggestionExclusionStore.activeKeys(in: context)
        let ids = snapshot.baseInput.candidates.map(\.id)
        return Set(ids.filter { id in
            keys.contains { ExerciseSuggestionExclusionKey.matches($0, candidateID: id) }
        })
    }
}
