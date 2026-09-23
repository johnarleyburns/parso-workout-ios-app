import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

extension HomeView {
    func requestSuggestedWorkout(_ modality: SuggestedWorkoutModality) {
        switch modality {
        case .strength:
            requestSuggestedStrength()
        case .cardio:
            requestSuggestedCardio()
        }
    }

    /// Captures SwiftData values on the main actor, then lets the sheet run the
    /// pure, Sendable generator without carrying managed objects across actors.
    private func requestSuggestedStrength() {
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

    /// Captures only value data from recorded cardio. The generator never sees
    /// SwiftData objects, HR samples, routes, or the main-actor dashboard.
    private func requestSuggestedCardio() {
        Haptics.selection()
        let history = cardio.compactMap { workout -> CardioSuggestionHistory? in
            guard workout.deletedAt == nil, workout.end != nil, workout.duration > 0 else {
                return nil
            }
            let summary = workout.intensitySummary
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
            let moderateEquivalent = summary?.moderateEquivalentMinutes
                ?? workout.duration / 60
                    * ((workout.typeValue == .hiit || workout.typeValue == .boxing) ? 2 : 1)
            return CardioSuggestionHistory(
                type: workout.typeValue,
                durationMinutes: actualDuration / 60,
                moderateEquivalentMinutes: moderateEquivalent,
                intensity: intensity,
                isInterval: workout.intervalSummary != nil
                    || workout.typeValue == .hiit
                    || workout.typeValue == .boxing,
                isIndoor: workout.typeValue.usesGPS ? workout.orderedRouteSamples.isEmpty : true,
                start: workout.start)
        }
        let input = CardioSuggestionInput(
            history: history,
            weeklyModerateEquivalentMinutes: dashboard.cardioDetail.moderateEquivalentMinutes,
            weeklyTargetMinutes: dashboard.cardioDetail.targetMinutes,
            experience: settings.experienceLevel,
            asOf: Date())
        presentSuggestedCardio(input)
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

    private func presentSuggestedCardio(_ input: CardioSuggestionInput) {
        if selectWorkoutPresented || weightsStartPresented || cardioPickerPresented {
            pendingSuggestedCardioInput = input
            selectWorkoutPresented = false
            weightsStartPresented = false
            cardioPickerPresented = false
        } else {
            generateAndOpenSuggestedCardio(input)
        }
    }

    /// Called from the originating sheet's `onDismiss`. This is the only place
    /// where a queued suggestion becomes presentable, so the old sheet and its
    /// NavigationStack are gone before the chooser is constructed.
    func presentPendingSuggestedWorkout() {
        guard !selectWorkoutPresented, !weightsStartPresented, !cardioPickerPresented else { return }
        if let request = pendingSuggestedWorkoutRequest {
            pendingSuggestedWorkoutRequest = nil
            generateAndOpenPersonalizedWorkout(request)
        } else if let input = pendingSuggestedCardioInput {
            pendingSuggestedCardioInput = nil
            generateAndOpenSuggestedCardio(input)
        }
    }

    private func generateAndOpenSuggestedCardio(_ input: CardioSuggestionInput) {
        cancelSuggestedCardioGeneration()
        suggestedCardioCalculating = true
        let task = Task {
            let suggestion = await Task.detached(priority: .userInitiated) {
                CardioSuggestionGenerator.generate(input: input)
            }.value
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard suggestedCardioTask != nil else { return }
                suggestedCardioCalculating = false
                suggestedCardioTask = nil
                guard let suggestion else {
                    suggestedCardioFailure = "No supported cardio history is available yet. Try again after recording a cardio workout."
                    return
                }
                suggestedCardio = suggestion
            }
        }
        suggestedCardioTask = task
    }

    private func generateAndOpenPersonalizedWorkout(_ request: SuggestedWorkoutRequest) {
        cancelSuggestedWorkoutGeneration()
        if let failure = request.failureMessage {
            suggestedWorkoutFailure = failure
            return
        }
        suggestedWorkoutCalculating = true
        let task = Task {
            let option = await Task.detached(priority: .userInitiated) {
                SuggestedWorkoutGenerator.generatePersonalized(input: request.input)
            }.value
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard suggestedWorkoutTask != nil else { return }
                suggestedWorkoutCalculating = false
                suggestedWorkoutTask = nil
                guard option.isLaunchable else {
                    suggestedWorkoutFailure = "No usable exercise data is available yet. Try again to refresh the exercise catalog."
                    return
                }
                let plan = SuggestedWorkoutPresenter.editablePlan(
                    for: option, unit: request.unit,
                    warmupMinutes: request.warmupMinutes,
                    cooldownMinutes: request.cooldownMinutes)
                // Present the plan directly after the chooser has disappeared.
                // A NavigationPath push here can resolve against the nested
                // Start Workout stack during dismissal and land on the generic
                // missing-workout warning page instead of the plan editor.
                suggestedWorkoutPlan = plan
            }
        }
        suggestedWorkoutTask = task
    }

    func cancelSuggestedWorkoutGeneration() {
        suggestedWorkoutTask?.cancel()
        suggestedWorkoutTask = nil
        suggestedWorkoutCalculating = false
    }

    func cancelSuggestedCardioGeneration() {
        suggestedCardioTask?.cancel()
        suggestedCardioTask = nil
        suggestedCardioCalculating = false
    }

    /// A failed suggestion must leave the user at a usable next step. Keep
    /// manual strength/cardio entry separate so retrying cannot reopen a
    /// dismissed picker or create a second generation task.
    func chooseManualWorkout(_ modality: SuggestedWorkoutModality) {
        switch modality {
        case .strength:
            weightsStartPresented = true
        case .cardio:
            cardioPickerPresented = true
        }
    }
}
