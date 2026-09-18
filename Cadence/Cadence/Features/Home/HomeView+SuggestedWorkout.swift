import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

extension HomeView {
    /// Captures SwiftData values on the main actor, then lets the sheet run the
    /// pure, Sendable generator without carrying managed objects across actors.
    func requestSuggestedWorkout() {
        Haptics.selection()
        do {
            let activeSessionID = active.strengthSession?.id
            let completedHistorySessions = sessions.filter {
                $0.id != activeSessionID && $0.countsAsStrengthHistory
            }
            let historyWorkingSetCount = completedHistorySessions.reduce(0) { count, session in
                count + session.completedOwnerWorkingSetCount
            }
            let historyWorkoutCount = completedHistorySessions.filter { session in
                session.completedOwnerWorkingSetCount > 0
            }.count
            // Personalized history is a complete per-exercise projection, not a
            // newest-first set scan. The first request backfills every existing
            // workout (including legacy installs with 100+ workouts); subsequent
            // requests read the compact index and rebuild only when its source
            // signature changes.
            let historyExerciseKeys = try ExerciseHistoryIndexStore.personalizedExerciseKeys(
                sessions: completedHistorySessions,
                storageURL: model.isUITestMode ? nil : ExerciseHistoryIndexStore.defaultStorageURL())

            let persistedCandidates = try SuggestedWorkoutSignposts.exerciseFetchAndMap {
                try WorkoutRepository.allExercises(context).map { exercise in
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
                        isPersonalized: historyExerciseKeys.contains(
                            ExerciseSuggestionExclusionKey.forExercise(exercise)))
                }
            }
            // Production seeding is intentionally deferred so launch stays
            // responsive. A user can reach this action before that background
            // seed finishes, and older stores can contain rows without the
            // facets the solver needs. The canonical value catalog keeps the
            // chooser launchable in both cases without creating SwiftData rows
            // merely to display a suggestion.
            let candidates: [SuggestedExerciseCandidate]
            let trackedMuscleIDs = Set(settings.coachSchedulePreferences.trackedMuscleGroups
                .map(\.rawValue))
            let persistedCatalogIsUsable = persistedCandidates.contains {
                guard $0.volumeEligible else { return false }
                return ($0.primaryMuscles + $0.secondaryMuscles).contains {
                    guard let group = MuscleGroup.canonical($0) else { return false }
                    return trackedMuscleIDs.isEmpty || trackedMuscleIDs.contains(group.rawValue)
                }
            } && persistedCandidates.contains(where: { $0.matches(.bodyweight) })
            let exclusionKeys = try ExerciseSuggestionExclusionStore.activeKeys(in: context)
            if persistedCatalogIsUsable {
                candidates = SuggestedExerciseFilter.excluding(persistedCandidates, keys: exclusionKeys)
            } else {
                let starterCandidates = ExerciseLibrary.starter.map { template in
                    let candidate = SuggestedExerciseCandidate(template: template)
                    return SuggestedExerciseCandidate(
                        id: candidate.id,
                        name: candidate.name,
                        mechanics: candidate.mechanics,
                        primaryMuscles: candidate.primaryMuscles,
                        secondaryMuscles: candidate.secondaryMuscles,
                        equipment: candidate.equipment,
                        volumeEligible: candidate.volumeEligible,
                        trainingTypes: candidate.trainingTypes,
                        modalities: candidate.modalities,
                        sportContexts: candidate.sportContexts,
                        isPersonalized: historyExerciseKeys.contains(candidate.id))
                }
                // Keep a user's own historical movements even while the
                // asynchronous catalog seed is incomplete. General styles use
                // the canonical starter fallback; Personalized must never lose
                // a custom or newly imported movement just because that fallback
                // is active.
                let historicalCandidates = persistedCandidates.filter(\.isPersonalized)
                candidates = SuggestedExerciseFilter.excluding(
                    starterCandidates + historicalCandidates,
                    keys: exclusionKeys)
            }
            let historyData = historyWorkingSetCount > 0
                ? TrainingEngineBridge.historyData(from: completedHistorySessions,
                                                   subjectId: "cladiron-local")
                : nil
            let asOf = Date()
            let request = SuggestedWorkoutRequest(
                input: SuggestedWorkoutInput(
                    completedSetsByMuscle: coachFacts.weeklySetsByMuscle,
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
                        asOf: asOf)),
                unit: settings.unit,
                warmupMinutes: settings.warmupMinutes,
                cooldownMinutes: settings.cooldownMinutes)
            presentSuggestedWorkout(request)
        } catch {
            // Generation has no safe partial candidate snapshot to present when
            // the catalog fetch fails, so show a retryable error at Home.
            presentSuggestedWorkout(SuggestedWorkoutRequest(
                input: SuggestedWorkoutInput(completedSetsByMuscle: coachFacts.weeklySetsByMuscle,
                                              candidates: [],
                                              trackedGroups: settings.coachSchedulePreferences.trackedMuscleGroups,
                                              preferredSetsPerExercise: settings.coachSchedulePreferences.desiredSetsPerExercise,
                                              trainingGoal: settings.trainingGoal,
                                              preferredStyle: settings.preferredWorkoutStyle,
                                              engineContext: SuggestedWorkoutEngineContext(
                                                  experience: settings.experienceLevel,
                                                  schedule: settings.coachSchedulePreferences,
                                                  availableEquipment: Equipment.allCases,
                                                  environment: "commercial_gym",
                                                  asOf: Date())),
                unit: settings.unit,
                warmupMinutes: settings.warmupMinutes,
                cooldownMinutes: settings.cooldownMinutes,
                failureMessage: "Exercise data could not be read. Try again to refresh the exercise catalog."))
        }
    }

    private func presentSuggestedWorkout(_ request: SuggestedWorkoutRequest) {
        if selectWorkoutPresented || weightsStartPresented || cardioPickerPresented {
            pendingSuggestedWorkoutRequest = request
            selectWorkoutPresented = false
            weightsStartPresented = false
            cardioPickerPresented = false
        } else {
            generateAndOpenPersonalizedWorkout(request)
        }
    }

    /// Called from the originating sheet's `onDismiss`. This is the only place
    /// where a queued suggestion becomes presentable, so the old sheet and its
    /// NavigationStack are gone before the chooser is constructed.
    func presentPendingSuggestedWorkout() {
        guard !selectWorkoutPresented,
              !weightsStartPresented,
              !cardioPickerPresented,
              let request = pendingSuggestedWorkoutRequest else { return }
        pendingSuggestedWorkoutRequest = nil
        generateAndOpenPersonalizedWorkout(request)
    }

    private func generateAndOpenPersonalizedWorkout(_ request: SuggestedWorkoutRequest) {
        guard !suggestedWorkoutCalculating else { return }
        if let failure = request.failureMessage {
            suggestedWorkoutFailure = failure
            return
        }
        suggestedWorkoutCalculating = true
        Task {
            let option = await Task.detached(priority: .userInitiated) {
                SuggestedWorkoutGenerator.generatePersonalized(input: request.input)
            }.value
            guard !Task.isCancelled else { return }
            await MainActor.run {
                suggestedWorkoutCalculating = false
                guard option.isLaunchable else {
                    suggestedWorkoutFailure = "No usable exercise data is available yet. Try again to refresh the exercise catalog."
                    return
                }
                let plan = SuggestedWorkoutPresenter.editablePlan(
                    for: option, unit: request.unit,
                    warmupMinutes: request.warmupMinutes,
                    cooldownMinutes: request.cooldownMinutes)
                path.append(HomeRoute.workoutEditor(plan))
            }
        }
    }
}
