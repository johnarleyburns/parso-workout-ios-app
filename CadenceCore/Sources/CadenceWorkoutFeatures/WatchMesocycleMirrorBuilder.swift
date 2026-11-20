#if canImport(SwiftData)
import CadenceCore
import CadenceFeatures
import Foundation
import SwiftData

/// Phone-side builder for the 12-week Watch mirror. The phone is the only
/// CloudKit writer; this value is the Watch's read-only copy for local
/// strength/cardio generation. History is pruned to the mesocycle window, while
/// all-time counts and the candidate catalog are carried as parity metadata.
public enum WatchMesocycleMirrorBuilder {
    public static func make(
        context: ModelContext,
        settings: AppSettings,
        now: Date = Date(),
        activeSessionID: UUID? = nil,
        historyIndexStorageURL: URL? = ExerciseHistoryIndexStore.defaultStorageURL()
    ) throws -> WatchMesocycleMirror {
        let allStrength = try WorkoutRepository.allSessions(context)
            .filter { $0.id != activeSessionID && $0.countsAsStrengthHistory }
        let allTimeWorkoutCount = allStrength.filter { $0.completedOwnerWorkingSetCount > 0 }.count
        let allTimeWorkingSetCount = allStrength.reduce(0) { $0 + $1.completedOwnerWorkingSetCount }

        let windowStart = now.addingTimeInterval(
            -Double(WatchMesocycleMirror.historyWindowDays) * 86_400)
        let windowed = allStrength.filter { $0.date >= windowStart && $0.date <= now }

        var exercisesByID: [String: WatchMesocycleMirror.Exercise] = [:]
        var strengthSessions: [WatchMesocycleMirror.StrengthSession] = []
        for session in windowed.sorted(by: { $0.date > $1.date }) {
            let ownerWorking = session.orderedSets.filter {
                !$0.isWarmup && $0.isOwnerSet && $0.reps > 0
            }
            guard !ownerWorking.isEmpty else { continue }
            let sets = ownerWorking.prefix(WatchMesocycleMirror.maxSetsPerSession).compactMap { set
                -> WatchMesocycleMirror.StrengthSet? in
                guard let exercise = set.exercise else { return nil }
                let id = ExerciseSuggestionExclusionKey.forExercise(exercise)
                exercisesByID[id] = WatchMesocycleMirror.Exercise(
                    id: id,
                    name: exercise.name,
                    primaryMuscles: exercise.primaryMuscles,
                    secondaryMuscles: exercise.secondaryMuscles,
                    directMuscles: exercise.directMuscles.map(\.rawValue),
                    indirectMuscles: exercise.indirectMuscles.map(\.rawValue),
                    volumeEligible: exercise.volumeEligible)
                return WatchMesocycleMirror.StrengthSet(
                    exerciseID: id,
                    exerciseName: exercise.name,
                    reps: set.reps,
                    weightKg: set.weight)
            }
            guard !sets.isEmpty else { continue }
            strengthSessions.append(WatchMesocycleMirror.StrengthSession(
                id: session.id,
                date: session.date,
                endedAt: session.endedAt,
                sets: Array(sets)))
        }

        let candidates = try candidates(context: context, sessions: allStrength,
                                        settings: settings,
                                        historyIndexStorageURL: historyIndexStorageURL)
        let cardio = try cardioSessions(context: context, now: now, windowStart: windowStart)
        let latest = allStrength
            .filter { $0.completedOwnerWorkingSetCount > 0 }
            .max { ($0.endedAt ?? $0.date) < ($1.endedAt ?? $1.date) }
        let latestNames = latest?.orderedSets
            .filter { !$0.isWarmup && $0.isOwnerSet && $0.reps > 0 }
            .compactMap(\.exercise?.name) ?? []
        let latestKeys = Set(latestNames.map(ExerciseSuggestionExclusionKey.forName))
        let recentIDs = Set(candidates.filter {
            latestKeys.contains(ExerciseSuggestionExclusionKey.forName($0.name))
        }.map(\.id))
        let mostRecentSets: Int? = {
            guard let last = latestNames.last else { return nil }
            let count = latestNames.filter { $0 == last }.count
            return count > 0 ? count : nil
        }()
        let schedule = settings.coachSchedulePreferences
        let engine = SuggestedWorkoutEngineContext(
            experience: settings.experienceLevel,
            schedule: schedule,
            availableEquipment: Equipment.allCases,
            environment: "commercial_gym",
            asOf: now)
        let coachSettings = WatchMesocycleMirror.CoachSettings(
            trainingGoal: settings.trainingGoal,
            experience: settings.experienceLevel,
            preferredStyle: settings.preferredWorkoutStyle,
            schedule: schedule,
            trackedGroups: schedule.trackedMuscleGroups,
            preferredSetsPerExercise: schedule.desiredSetsPerExercise,
            unit: settings.unit,
            warmupMinutes: settings.warmupMinutes,
            cooldownMinutes: settings.cooldownMinutes,
            engineContext: engine,
            excludedCardioTypes: settings.excludedCardioTypes,
            excludedHIITProtocolIDs: Set(settings.excludedHIITProtocolIDs),
            weeklyCardioTargetMinutes: WeeklyCardioProgress.target)
        return WatchMesocycleMirror(
            generatedAt: now,
            coachSettings: coachSettings,
            allTimeWorkoutCount: allTimeWorkoutCount,
            allTimeWorkingSetCount: allTimeWorkingSetCount,
            recentlyCompletedCandidateIDs: recentIDs,
            mostRecentExerciseWorkingSets: mostRecentSets,
            strengthSessions: strengthSessions,
            exercises: exercisesByID,
            candidates: candidates,
            cardioSessions: cardio)
    }

    /// Mirrors `TodaySuggestionLaunchBuilder`: the same catalog, personalized
    /// flags, starter fallback, and permanent exclusions the phone uses.
    private static func candidates(context: ModelContext,
                                   sessions: [WorkoutSession],
                                   settings: AppSettings,
                                   historyIndexStorageURL: URL?) throws -> [SuggestedExerciseCandidate] {
        let historyKeys = try ExerciseHistoryIndexStore.personalizedExerciseKeys(
            sessions: sessions,
            storageURL: historyIndexStorageURL)
        let exercises = try WorkoutRepository.allExercises(context)
        let persisted = exercises.map { exercise -> SuggestedExerciseCandidate in
            let id = ExerciseSuggestionExclusionKey.forExercise(exercise)
            return SuggestedExerciseCandidate(
                id: id,
                name: exercise.name,
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
        let tracked = Set(settings.coachSchedulePreferences.trackedMuscleGroups.map(\.rawValue))
        let usable = persisted.contains { candidate in
            guard candidate.volumeEligible else { return false }
            return (candidate.primaryMuscles + candidate.secondaryMuscles).contains { muscle in
                guard let group = MuscleGroup.canonical(muscle) else { return false }
                return tracked.isEmpty || tracked.contains(group.rawValue)
            }
        } && persisted.contains(where: { $0.matches(.bodyweight) })
        let exclusions = try ExerciseSuggestionExclusionStore.activeKeys(in: context)
        if usable {
            return SuggestedExerciseFilter.excluding(persisted, keys: exclusions)
        }
        let starter = ExerciseLibrary.starter.map { template -> SuggestedExerciseCandidate in
            let base = SuggestedExerciseCandidate(template: template)
            return SuggestedExerciseCandidate(
                id: base.id,
                name: base.name,
                mechanics: base.mechanics,
                primaryMuscles: base.primaryMuscles,
                secondaryMuscles: base.secondaryMuscles,
                equipment: base.equipment,
                volumeEligible: base.volumeEligible,
                trainingTypes: base.trainingTypes,
                modalities: base.modalities,
                sportContexts: base.sportContexts,
                isPersonalized: historyKeys.contains(base.id))
        }
        return SuggestedExerciseFilter.excluding(
            starter + persisted.filter(\.isPersonalized), keys: exclusions)
    }

    /// Mirrors the phone's `cardioSuggestionInput` interpretation of a stored
    /// cardio row so the Watch sees the same duration/intensity/credit values.
    private static func cardioSessions(context: ModelContext,
                                       now: Date,
                                       windowStart: Date) throws -> [WatchMesocycleMirror.CardioSession] {
        let decoder = JSONDecoder()
        return try WorkoutRepository.allCardio(context)
            .filter {
                $0.deletedAt == nil && $0.end != nil && $0.duration > 0
                    && $0.start >= windowStart && $0.start <= now
            }
            .prefix(WatchMesocycleMirror.maxCardioSessions)
            .map { workout in
                let summary = workout.intensitySummaryData.data(using: .utf8)
                    .flatMap { try? decoder.decode(CardioMinuteSummary.self, from: $0) }
                let actualDuration = summary?.actualDuration ?? workout.duration
                let intensity: RelativeIntensity
                if let summary, summary.actualDuration > 0 {
                    let vigorousFraction = summary.vigorousDuration / summary.actualDuration
                    let moderateFraction = summary.moderateDuration / summary.actualDuration
                    if vigorousFraction >= 0.5 {
                        intensity = .vigorous
                    } else if moderateFraction >= 0.5 {
                        intensity = .moderate
                    } else {
                        intensity = .light
                    }
                } else {
                    intensity = .unknown
                }
                let type = workout.typeValue
                let moderateEquivalent = summary?.moderateEquivalentMinutes
                    ?? workout.duration / 60
                        * ((type == .hiit || type == .boxing) ? 2 : 1)
                return WatchMesocycleMirror.CardioSession(
                    id: workout.id,
                    type: type,
                    durationMinutes: actualDuration / 60,
                    moderateEquivalentMinutes: moderateEquivalent,
                    intensity: intensity,
                    isInterval: !workout.intervalDetailData.isEmpty
                        || type == .hiit || type == .boxing,
                    isIndoor: type.usesGPS ? nil : true,
                    start: workout.start)
            }
    }
}
#endif
