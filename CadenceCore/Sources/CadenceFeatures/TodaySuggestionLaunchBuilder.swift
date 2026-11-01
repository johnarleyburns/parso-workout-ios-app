import Foundation
import SwiftData
import CadenceCore

/// Value copy of the settings that decide the automatic Today suggestion.
/// Captured on the main actor, then handed to the background builder.
public struct TodaySuggestionSettingsSnapshot: Sendable, Equatable {
    public let unit: MeasurementUnitPreference
    public let warmupMinutes: Int
    public let cooldownMinutes: Int
    public let trainingGoal: TrainingGoal
    public let preferredStyle: SuggestedWorkoutStyle
    public let experience: ExperienceLevel
    public let formula: OneRepMaxFormula
    public let schedule: CoachSchedulePreferences
    /// `nil` keeps the exercise-history index in memory (UI-test mode).
    public let historyIndexStorageURL: URL?

    public init(unit: MeasurementUnitPreference, warmupMinutes: Int, cooldownMinutes: Int,
                trainingGoal: TrainingGoal, preferredStyle: SuggestedWorkoutStyle,
                experience: ExperienceLevel, formula: OneRepMaxFormula,
                schedule: CoachSchedulePreferences, historyIndexStorageURL: URL?) {
        self.unit = unit
        self.warmupMinutes = warmupMinutes
        self.cooldownMinutes = cooldownMinutes
        self.trainingGoal = trainingGoal
        self.preferredStyle = preferredStyle
        self.experience = experience
        self.formula = formula
        self.schedule = schedule
        self.historyIndexStorageURL = historyIndexStorageURL
    }

    public init(_ settings: AppSettings, historyIndexStorageURL: URL?) {
        self.init(unit: settings.unit, warmupMinutes: settings.warmupMinutes,
                  cooldownMinutes: settings.cooldownMinutes, trainingGoal: settings.trainingGoal,
                  preferredStyle: settings.preferredWorkoutStyle, experience: settings.experienceLevel,
                  formula: settings.formula, schedule: settings.coachSchedulePreferences,
                  historyIndexStorageURL: historyIndexStorageURL)
    }
}

/// Immutable, value-only result of the background Today-suggestion extraction.
/// Never holds a model object, context, closure or view state.
public struct TodaySuggestionLaunchSnapshot: Sendable, Equatable {
    public let earlyKey: String
    public let hasMinimumHistory: Bool
    public let request: CoachSuggestionRequest?
    /// Stable scheduled-workout stamps folded into the full fingerprint.
    public let scheduledStamps: [String]
}

public enum TodaySuggestionLaunchBuilder {
    public static func scheduledStamps(_ scheduled: [ScheduledWorkout]) -> [String] {
        scheduled.map {
            "\($0.id)|\($0.scheduledDate.timeIntervalSince1970)|\($0.updatedAt.timeIntervalSince1970)|\($0.statusRaw)|\($0.payloadVersion)"
        }.sorted()
    }

    public static func earlyKey(sessions: [WorkoutSession], catalogCount: Int,
                                scheduledStamps: [String], exclusions: Set<String>,
                                activeSessionID: UUID?,
                                settings: TodaySuggestionSettingsSnapshot) -> String {
        let history = sessions.filter { $0.id != activeSessionID && $0.countsAsStrengthHistory }
            .map { "\($0.id)|\($0.date.timeIntervalSince1970)|\($0.endedAt?.timeIntervalSince1970 ?? 0)|\($0.completedOwnerWorkingSetCount)" }
            .sorted()
        return TodaySuggestedWorkoutEarlyKey.make([
            String(describing: settings.unit), "\(settings.warmupMinutes)", "\(settings.cooldownMinutes)",
            String(describing: settings.trainingGoal), String(describing: settings.preferredStyle),
            String(describing: settings.experience),
            String(describing: settings.schedule),
            "catalog:\(catalogCount)"
        ] + history.map { "h:" + $0 } + exclusions.sorted().map { "e:" + $0 }
          + scheduledStamps.map { "x:" + $0 })
    }

    public static func candidate(_ exercise: Exercise, isPersonalized: Bool) -> SuggestedExerciseCandidate {
        SuggestedExerciseCandidate(
            id: ExerciseSuggestionExclusionKey.forExercise(exercise),
            name: exercise.name,
            mechanics: exercise.mechanicsValue ?? .compound,
            primaryMuscles: exercise.primaryMuscles,
            secondaryMuscles: exercise.secondaryMuscles,
            equipment: exercise.equipmentValue,
            volumeEligible: exercise.volumeEligible,
            trainingTypes: exercise.trainingTypes,
            modalities: exercise.modalities,
            sportContexts: exercise.sportContexts,
            isPersonalized: isPersonalized)
    }

    /// Runs entirely on the caller's (background) context; returns only values.
    public static func make(sessions: [WorkoutSession], exercises: [Exercise],
                            scheduled: [ScheduledWorkout], exclusions: Set<String>,
                            activeSessionID: UUID?, settings: TodaySuggestionSettingsSnapshot,
                            asOf: Date = Date()) throws -> TodaySuggestionLaunchSnapshot {
        let stamps = scheduledStamps(scheduled)
        let key = earlyKey(sessions: sessions, catalogCount: exercises.count,
                           scheduledStamps: stamps, exclusions: exclusions,
                           activeSessionID: activeSessionID, settings: settings)
        let hasMinimum = sessions.lazy.filter { $0.countsAsStrengthHistory }.prefix(2).count >= 2
        guard hasMinimum else {
            return TodaySuggestionLaunchSnapshot(earlyKey: key, hasMinimumHistory: false,
                                                 request: nil, scheduledStamps: stamps)
        }
        let history = sessions.filter { $0.id != activeSessionID && $0.countsAsStrengthHistory }
        let workingSets = history.reduce(0) { $0 + $1.completedOwnerWorkingSetCount }
        let workoutCount = history.filter { $0.completedOwnerWorkingSetCount > 0 }.count
        let facts = TrainingFacts.make(sessions: history, now: asOf, goal: settings.trainingGoal,
                                       experience: settings.experience, formula: settings.formula)
        let historyKeys = try ExerciseHistoryIndexStore.personalizedExerciseKeys(
            sessions: history, storageURL: settings.historyIndexStorageURL)
        let persisted = exercises.map {
            candidate($0, isPersonalized: historyKeys.contains(ExerciseSuggestionExclusionKey.forExercise($0)))
        }
        let tracked = Set(settings.schedule.trackedMuscleGroups.map(\.rawValue))
        let usable = persisted.contains {
            guard $0.volumeEligible else { return false }
            return ($0.primaryMuscles + $0.secondaryMuscles).contains {
                guard let group = MuscleGroup.canonical($0) else { return false }
                return tracked.isEmpty || tracked.contains(group.rawValue)
            }
        } && persisted.contains(where: { $0.matches(.bodyweight) })
        let candidates: [SuggestedExerciseCandidate]
        if usable {
            candidates = SuggestedExerciseFilter.excluding(persisted, keys: exclusions)
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
            candidates = SuggestedExerciseFilter.excluding(
                starter + persisted.filter(\.isPersonalized), keys: exclusions)
        }
        let input = SuggestedWorkoutInput(
            completedSetsByMuscle: facts.weeklySetsByMuscle,
            candidates: candidates,
            historyData: workingSets > 0
                ? TrainingEngineBridge.historyData(from: history, subjectId: "cladiron-local") : nil,
            historyWorkoutCount: workoutCount,
            historyWorkingSetCount: workingSets,
            recentlyCompletedCandidateIDs: RecentSuggestionExclusion.candidateIDs(
                sessions: history, candidates: candidates),
            trackedGroups: settings.schedule.trackedMuscleGroups,
            preferredSetsPerExercise: settings.schedule.desiredSetsPerExercise,
            mostRecentExerciseWorkingSets: RecentSuggestionExclusion.mostRecentExerciseSetCount(sessions: history),
            trainingGoal: settings.trainingGoal,
            preferredStyle: settings.preferredStyle,
            engineContext: SuggestedWorkoutEngineContext(
                experience: settings.experience, schedule: settings.schedule,
                availableEquipment: Equipment.allCases, environment: "commercial_gym", asOf: asOf))
        return TodaySuggestionLaunchSnapshot(
            earlyKey: key, hasMinimumHistory: true,
            request: CoachSuggestionRequest(input: input, unit: settings.unit,
                                            warmupMinutes: settings.warmupMinutes,
                                            cooldownMinutes: settings.cooldownMinutes),
            scheduledStamps: stamps)
    }

    /// Fetches on `context` (a background context) and builds the snapshot.
    public static func load(in context: ModelContext, activeSessionID: UUID?,
                            settings: TodaySuggestionSettingsSnapshot) throws -> TodaySuggestionLaunchSnapshot {
        try make(
            sessions: try WorkoutRepository.allSessions(context),
            exercises: try WorkoutRepository.allExercises(context),
            scheduled: try context.fetch(FetchDescriptor<ScheduledWorkout>(
                sortBy: [SortDescriptor(\.scheduledDate), SortDescriptor(\.title)])),
            exclusions: try ExerciseSuggestionExclusionStore.activeKeys(in: context),
            activeSessionID: activeSessionID, settings: settings)
    }
}
