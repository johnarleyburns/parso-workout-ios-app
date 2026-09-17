import Foundation
import SwiftData
import CadenceCore
import CadenceFeatures

/// Immutable input for the single-exercise chooser. SwiftData objects stop at
/// this boundary; the generator can therefore run away from the main actor.
struct SuggestedExerciseRequest: Identifiable {
    let id = UUID()
    let input: SuggestedWorkoutInput
    let style: SuggestedWorkoutStyle
    let alreadyAllocatedByMuscle: [String: Double]
    let excludingCandidateIDs: Set<String>
}

/// Builds the same catalog and history snapshot used by full suggested plans.
/// This intentionally runs only after the user taps “Suggest Exercise…”.
enum SuggestedExerciseRequestFactory {
    @MainActor
    static func make(context: ModelContext,
                     settings: AppSettings,
                     style: SuggestedWorkoutStyle,
                     existingExerciseNames: [String],
                     alreadyAllocatedByMuscle: [String: Double],
                     excludingSessionID: UUID? = nil) throws -> SuggestedExerciseRequest {
        let allSessions = try WorkoutRepository.allSessions(context)
        let history = allSessions.filter {
            $0.id != excludingSessionID && $0.countsAsStrengthHistory
        }
        let historyWorkingSetCount = history.reduce(0) { $0 + $1.completedOwnerWorkingSetCount }
        let historyWorkoutCount = history.filter { $0.completedOwnerWorkingSetCount > 0 }.count
        let historyKeys = try ExerciseHistoryIndexStore.personalizedExerciseKeys(
            sessions: history,
            storageURL: ExerciseHistoryIndexStore.defaultStorageURL())
        let exercises = try WorkoutRepository.allExercises(context)
        let trackedIDs = Set(settings.coachSchedulePreferences.trackedMuscleGroups.map(\.rawValue))
        let persisted = exercises.map { exercise in
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
                isPersonalized: historyKeys.contains(ExerciseSuggestionExclusionKey.forExercise(exercise)))
        }
        let usable = persisted.contains { candidate in
            candidate.volumeEligible &&
            (candidate.primaryMuscles + candidate.secondaryMuscles).contains { muscle in
                guard let group = MuscleGroup.canonical(muscle) else { return false }
                return trackedIDs.isEmpty || trackedIDs.contains(group.rawValue)
            }
        }
        let exclusionKeys = try ExerciseSuggestionExclusionStore.activeKeys(in: context)
        let candidates: [SuggestedExerciseCandidate]
        if usable {
            candidates = SuggestedExerciseFilter.excluding(persisted, keys: exclusionKeys)
        } else {
            let starter = ExerciseLibrary.starter.map { template in
                let candidate = SuggestedExerciseCandidate(template: template)
                return SuggestedExerciseCandidate(
                    id: candidate.id, name: candidate.name, mechanics: candidate.mechanics,
                    primaryMuscles: candidate.primaryMuscles,
                    secondaryMuscles: candidate.secondaryMuscles,
                    equipment: candidate.equipment, volumeEligible: candidate.volumeEligible,
                    trainingTypes: candidate.trainingTypes, modalities: candidate.modalities,
                    sportContexts: candidate.sportContexts,
                    isPersonalized: historyKeys.contains(candidate.id))
            }
            let historical = persisted.filter(\.isPersonalized)
            candidates = SuggestedExerciseFilter.excluding(starter + historical,
                                                            keys: exclusionKeys)
        }
        let normalizedExisting = Set(existingExerciseNames.map { $0.localizedLowercase })
        let existingIDs = Set(candidates.filter {
            normalizedExisting.contains($0.name.localizedLowercase)
        }.map(\.id))
        let facts = TrainingFacts.make(sessions: history,
                                       goal: settings.trainingGoal,
                                       experience: settings.experienceLevel)
        let historyData = historyWorkingSetCount > 0
            ? TrainingEngineBridge.historyData(from: history, subjectId: "cladiron-local")
            : nil
        let input = SuggestedWorkoutInput(
            completedSetsByMuscle: facts.weeklySetsByMuscle,
            candidates: candidates,
            historyData: historyData,
            historyWorkoutCount: historyWorkoutCount,
            historyWorkingSetCount: historyWorkingSetCount,
            trackedGroups: settings.coachSchedulePreferences.trackedMuscleGroups,
            preferredSetsPerExercise: settings.coachSchedulePreferences.desiredSetsPerExercise,
            trainingGoal: settings.trainingGoal,
            preferredStyle: settings.preferredWorkoutStyle,
            engineContext: SuggestedWorkoutEngineContext(
                experience: settings.experienceLevel,
                schedule: settings.coachSchedulePreferences,
                availableEquipment: Equipment.allCases,
                environment: "commercial_gym",
                asOf: Date()))
        return SuggestedExerciseRequest(input: input,
                                        style: style,
                                        alreadyAllocatedByMuscle: alreadyAllocatedByMuscle,
                                        excludingCandidateIDs: existingIDs)
    }
}
