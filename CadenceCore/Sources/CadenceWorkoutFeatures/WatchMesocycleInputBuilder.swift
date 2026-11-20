import CadenceCore
import CadenceFeatures
import Foundation

/// Pure Watch-side input assembly. It uses only the mirrored 12-week history
/// and the phone's settings/candidate metadata, so the Watch runs the same
/// `generatePersonalized` / `CardioSuggestionGenerator` path as the phone.
public enum WatchMesocycleInputBuilder {
    // MARK: - Strength

    public static func strengthRequest(from mirror: WatchMesocycleMirror,
                                       now: Date = Date()) -> CoachSuggestionRequest? {
        guard mirror.schemaVersion == WatchMesocycleMirror.currentSchemaVersion,
              !mirror.candidates.isEmpty else { return nil }
        let settings = mirror.coachSettings
        let currentWeekStart = WeeklyStats.weekStart(now: now)
        let windowStart = now.addingTimeInterval(-Double(WatchMesocycleMirror.historyWindowDays) * 86_400)
        let sessions = mirror.strengthSessions.filter { $0.date >= windowStart && $0.date <= now }
        let weeklySets = completedSetsByMuscle(sessions: sessions,
                                               exercises: mirror.exercises,
                                               since: currentWeekStart,
                                               through: now)
        let recentIDs = mirror.recentlyCompletedCandidateIDs
        let mostRecentSets = mirror.mostRecentExerciseWorkingSets
        let input = SuggestedWorkoutInput(
            completedSetsByMuscle: weeklySets,
            candidates: mirror.candidates,
            historyData: nil,
            historyWorkoutCount: mirror.allTimeWorkoutCount,
            historyWorkingSetCount: mirror.allTimeWorkingSetCount,
            recentlyCompletedCandidateIDs: recentIDs,
            trackedGroups: settings.trackedGroups,
            preferredSetsPerExercise: settings.preferredSetsPerExercise,
            mostRecentExerciseWorkingSets: mostRecentSets,
            trainingGoal: settings.trainingGoal,
            preferredStyle: settings.preferredStyle,
            engineContext: settings.engineContext)
        return CoachSuggestionRequest(input: input,
                                      unit: settings.unit,
                                      warmupMinutes: settings.warmupMinutes,
                                      cooldownMinutes: settings.cooldownMinutes)
    }

    /// Strength input for the in-workout "Suggest exercise" shell. Adds the
    /// active workout's allocation and excludes its exercises, exactly like the
    /// phone's active-workout suggestion input.
    public static func strengthInput(from mirror: WatchMesocycleMirror,
                                     activeExerciseNames: [String] = [],
                                     activeWorkingSets: [WatchSuggestionSet] = [],
                                     transientExcludedCandidateIDs: Set<String> = [],
                                     now: Date = Date()) -> SuggestedWorkoutInput? {
        guard let base = strengthRequest(from: mirror, now: now)?.input else { return nil }
        let byName = Dictionary(
            mirror.candidates.map { (ExerciseLibrary.dedupKey($0.name), $0) },
            uniquingKeysWith: { first, _ in first })
        var excludedIDs = transientExcludedCandidateIDs
        var excludedNames = Set<String>()
        for name in activeExerciseNames {
            excludedNames.insert(ExerciseSuggestionExclusionKey.forName(name))
            if let candidate = byName[ExerciseLibrary.dedupKey(name)] {
                excludedIDs.insert(candidate.id)
            }
        }
        var allocated: [String: Double] = [:]
        for set in activeWorkingSets where !set.isWarmup {
            guard let candidate = byName[ExerciseLibrary.dedupKey(set.exerciseName)] else { continue }
            let primary = MuscleGroup.canonicalize(candidate.primaryMuscles)
            let secondary = MuscleGroup.canonicalize(candidate.secondaryMuscles)
                .filter { !primary.contains($0) }
            for (group, credit) in VolumeCredit.credits(
                direct: primary, indirect: secondary,
                volumeEligible: candidate.volumeEligible) where credit > 0 {
                allocated[group.rawValue, default: 0] += credit
            }
        }
        var sets = base.completedSetsByMuscle
        for (group, credit) in allocated {
            sets[group, default: 0] += credit
        }
        let candidates = base.candidates.filter { candidate in
            !excludedIDs.contains(candidate.id)
                && !excludedNames.contains(ExerciseSuggestionExclusionKey.forName(candidate.name))
        }
        return SuggestedWorkoutInput(
            completedSetsByMuscle: sets,
            candidates: candidates,
            historyData: base.historyData,
            historyWorkoutCount: base.historyWorkoutCount,
            historyWorkingSetCount: base.historyWorkingSetCount,
            recentlyCompletedCandidateIDs: base.recentlyCompletedCandidateIDs,
            trackedGroups: base.trackedGroups,
            preferredSetsPerExercise: base.preferredSetsPerExercise,
            mostRecentExerciseWorkingSets: base.mostRecentExerciseWorkingSets,
            trainingGoal: base.trainingGoal,
            preferredStyle: base.preferredStyle,
            engineContext: base.engineContext)
    }

    /// The exact shared path the phone uses: snapshot -> `generatePersonalized`
    /// through `CoachSuggestionService`.
    public static func strengthLaunch(from mirror: WatchMesocycleMirror,
                                      now: Date = Date()) -> (launch: WatchLiftLaunch, citationIDs: [String])? {
        guard let request = strengthRequest(from: mirror, now: now) else { return nil }
        let snapshot = CoachSuggestionSnapshotBuilder.make(
            request: request,
            generatedAt: mirror.generatedAt)
        guard let option = CoachSuggestionService.generate(from: snapshot),
              let launch = CoachSuggestionWatchBridge.launch(option: option, request: request) else {
            return nil
        }
        return (launch, option.citationIDs)
    }

    // MARK: - Cardio

    public static func cardioInput(from mirror: WatchMesocycleMirror,
                                   now: Date = Date()) -> CardioSuggestionInput {
        let settings = mirror.coachSettings
        let weekStart = WeeklyStats.weekStart(now: now)
        let history = mirror.cardioSessions.map { session in
            CardioSuggestionHistory(
                type: session.type,
                durationMinutes: session.durationMinutes,
                moderateEquivalentMinutes: session.moderateEquivalentMinutes,
                intensity: session.intensity,
                isInterval: session.isInterval,
                isIndoor: session.isIndoor,
                start: session.start)
        }
        let weeklyMinutes = mirror.cardioSessions
            .filter { $0.start >= weekStart && $0.start <= now }
            .reduce(0.0) { $0 + $1.moderateEquivalentMinutes }
        return CardioSuggestionInput(
            history: history,
            weeklyModerateEquivalentMinutes: weeklyMinutes,
            weeklyTargetMinutes: settings.weeklyCardioTargetMinutes,
            experience: settings.experience,
            asOf: now,
            excludedTypes: settings.excludedCardioTypes,
            excludedProtocolIDs: settings.excludedHIITProtocolIDs,
            skippedProtocolIDs: [])
    }

    public static func cardioSuggestion(from mirror: WatchMesocycleMirror,
                                        now: Date = Date()) -> CardioSuggestion? {
        CardioSuggestionGenerator.generate(input: cardioInput(from: mirror, now: now))
    }

    // MARK: - Helpers

    static func completedSetsByMuscle(sessions: [WatchMesocycleMirror.StrengthSession],
                                      exercises: [String: WatchMesocycleMirror.Exercise],
                                      since: Date,
                                      through: Date) -> [String: Double] {
        var result: [String: Double] = [:]
        for session in sessions where session.date >= since && session.date <= through {
            for set in session.sets where !set.isWarmup && set.reps > 0 {
                guard let exercise = exercises[set.exerciseID] else { continue }
                let direct = MuscleGroup.canonicalize(exercise.directMuscles)
                let indirect = MuscleGroup.canonicalize(exercise.indirectMuscles)
                let primary = direct.isEmpty && indirect.isEmpty
                    ? MuscleGroup.canonicalize(exercise.primaryMuscles)
                    : direct
                let secondary = (direct.isEmpty && indirect.isEmpty
                    ? MuscleGroup.canonicalize(exercise.secondaryMuscles)
                    : indirect)
                    .filter { !primary.contains($0) }
                for (group, credit) in VolumeCredit.credits(
                    direct: primary,
                    indirect: secondary,
                    volumeEligible: exercise.volumeEligible) where credit > 0 {
                    result[group.rawValue, default: 0] += credit
                }
            }
        }
        return result
    }

    static func candidateIDs(for session: WatchMesocycleMirror.StrengthSession,
                             candidates: [SuggestedExerciseCandidate]) -> Set<String> {
        let names = Set(session.sets.filter { !$0.isWarmup && $0.reps > 0 }
            .map { ExerciseSuggestionExclusionKey.forName($0.exerciseName) })
        guard !names.isEmpty else { return [] }
        return Set(candidates.filter {
            names.contains(ExerciseSuggestionExclusionKey.forName($0.name))
        }.map(\.id))
    }

    static func mostRecentExerciseSetCount(in session: WatchMesocycleMirror.StrengthSession) -> Int? {
        let names = session.sets.filter { !$0.isWarmup && $0.reps > 0 }.map(\.exerciseName)
        guard let last = names.last else { return nil }
        let count = names.filter { $0 == last }.count
        return count > 0 ? count : nil
    }
}
