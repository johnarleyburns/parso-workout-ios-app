import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures
import os

extension HomeView {
    private static let healthIngestLog = OSLog(subsystem: "guru.parso.cladiron", category: "HealthIngestion")
    var contributionPromptAllowed: Bool {
        active.strengthSession == nil && hrGateKind == nil && pending == nil && !warmupActive
    }

    static func dayString(_ date: Date = Date()) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: date)
    }

    /// Invalidates the history-derived surfaces after a save/log/ingest/delete.
    /// Yields one main-actor turn first so the SwiftData change has propagated to
    /// the `@Query` arrays before SwiftUI re-enters the computed Coach/week paths.
    func markWorkoutHistoryChanged() {
        Task { @MainActor in
            await Task.yield()
            historyRefreshToken = UUID()
        }
    }

    /// A genuine, user-completed workout (cardio/interval/swim/logged) was saved:
    /// refresh history AND count it toward the optional contribution prompt.
    /// HealthKit ingest (`syncCardioFromHealth`) intentionally does NOT count;
    /// strength completion is counted separately via `active.finishedSummary`.
    func workoutSaved() {
        markWorkoutHistoryChanged()
        ContributionCoordinator.recordWorkoutCompleted()
    }

    func startScheduledWorkout(_ record: ScheduledWorkout) {
        guard let plan = try? ScheduledWorkoutStore.decode(record.payloadData,
                                                           version: record.payloadVersion) else { return }
        scheduledWorkoutBeingStarted = record.id
        path.append(HomeRoute.workoutEditor(plan))
    }
    /// Pulls any new Watch/Health-recorded cardio into the local store (FR-2.1).
    /// This runs after Home loads and on pull-to-refresh. The status is published
    /// so the user can see what is happening instead of experiencing a silent
    /// background import.
    func syncCardioFromHealth() async {
        guard !model.healthSyncStatus.isInProgress else { return }
        let signpostID = OSSignpostID(log: Self.healthIngestLog)
        os_signpost(.begin, log: Self.healthIngestLog, name: "healthIngest", signpostID: signpostID)
        defer { os_signpost(.end, log: Self.healthIngestLog, name: "healthIngest", signpostID: signpostID) }
        model.healthSyncStatus = .syncing
        do {
            let new = await model.health.newWorkouts(since: model.lastHealthSync)
            guard !Task.isCancelled else {
                model.healthSyncStatus = .idle
                return
            }
            let inserted: Int
            if let cadenceModelContainer {
                inserted = await Task.detached(priority: .utility) {
                    let backgroundContext = ModelContext(cadenceModelContainer)
                    return (try? WorkoutRepository.ingest(new, in: backgroundContext)) ?? 0
                }.value
            } else {
                inserted = try WorkoutRepository.ingest(new, in: context)
            }
            let completedAt = Date()
            model.lastHealthSync = completedAt
            model.healthSyncStatus = .completed(completedAt, insertedCount: inserted)
            if inserted > 0 { markWorkoutHistoryChanged() }
        } catch {
            model.healthSyncStatus = .failed(error.localizedDescription)
        }
    }
    var homeActionRow: some View {
        VStack(spacing: CGFloat(LayoutMetrics.actionButtonSpacing)) {
            CadenceActionButton(title: "Start Workout", systemImage: "play.fill") {
                Haptics.selection()
                if active.liveWorkout.active != nil { showWorkoutConflict = true } else { selectWorkoutPresented = true }
            }
            .accessibilityIdentifier("home.startWorkout")
            Button {
                Haptics.selection()
                withAnimation(.easeInOut(duration: 0.18)) {
                    homeActionsExpanded.toggle()
                }
            } label: {
                HStack {
                    Text(homeActionsExpanded ? "Hide more actions" : "More actions")
                    Spacer()
                    Image(systemName: homeActionsExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .accessibilityIdentifier("home.moreActions")

            if homeActionsExpanded {
                CadenceActionButton(title: "Log Previous Workout",
                                    systemImage: "square.and.pencil",
                                    emphasis: .secondary) {
                    Haptics.selection()
                    logPickerPresented = true
                }
                .accessibilityIdentifier("home.logWorkout")
            }
        }
    }
    /// Workouts completed today; coach recommendations stay in the coach and
    /// Start Workout surfaces rather than appearing as historical activity.
    var workoutsTodayRows: [WorkoutsTodayPresenter.Row] {
        cachedWorkoutsTodayRows
    }

    /// Rebuilds historical display projections once per refresh rather than once
    /// for every SwiftUI body evaluation. Active set-entry changes do not alter
    /// these rows; completion and edits bump `historyRefreshToken`.
    func refreshHomeActivitySnapshot() {
        let signpostID = OSSignpostID(log: Self.healthIngestLog)
        os_signpost(.begin, log: Self.healthIngestLog, name: "homeActivityProjection", signpostID: signpostID)
        defer { os_signpost(.end, log: Self.healthIngestLog, name: "homeActivityProjection", signpostID: signpostID) }
        cachedWorkoutsTodayRows = WorkoutsTodayPresenter.historicalRows(
            sessions: sessions, cardio: cardio)
        let week = TodayActivityPresenter.weekEntries(sessions: sessions, cardio: cardio)
        cachedWeekStrengthEntries = week.strength
        cachedWeekCardioEntries = week.cardio
        cachedWeeklyVolumeKg = WeeklyStats.volumeKg(
            sessions.filter { $0.deletedAt == nil },
            since: WeeklyStats.weekStart())
    }
    func openTodayWorkout(_ row: WorkoutsTodayPresenter.Row) {
        guard let id = UUID(uuidString: row.sourceKey) else { return }
        switch row.modality {
        case .strength:
            if let s = sessions.first(where: { $0.id == id }) {
                path.append(HistorySummaryRoute.strength(s))
            }
        case .cardio:
            if let c = cardio.first(where: { $0.id == id }) { path.append(c) }
        }
    }
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

    var weekStripSection: some View {
        _ = historyRefreshToken
        return WeekStripView(
            plan: coachPlan,
            balance: coachDecision.weeklyBalance,
            preferences: settings.coachSchedulePreferences,
            onTap: {
                Haptics.selection()
                switch HomePlanPresenter.weekStripTapRoute() {
                case .yourPlan:
                    path.append(HomeRoute.plannedWorkouts)
                }
            }
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.weekStrip")
    }

    var weekActivity: (strength: [TodayActivityPresenter.Entry], cardio: [TodayActivityPresenter.Entry]) {
        (strength: cachedWeekStrengthEntries, cardio: cachedWeekCardioEntries)
    }
    func openWeekWorkout(_ entry: TodayActivityPresenter.Entry) {
        switch entry.kind {
        case .strength:
            if let s = sessions.first(where: { $0.id == entry.sourceId }) {
                path.append(HistorySummaryRoute.strength(s))
            }
        case .cardio:
            if let c = cardio.first(where: { $0.id == entry.sourceId }) { path.append(c) }
        }
    }
    func resumeCard(_ session: WorkoutSession) -> some View {
        Button {
            Haptics.selection()
            if active.strengthSession == nil {
                let heartbeat = WorkoutHeartbeatStore.read()
                active.adopt(session, heartbeat: heartbeat)
            }
            active.present()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "figure.strengthtraining.traditional").font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Resume \(session.title.isEmpty ? "Workout" : session.title)").font(.headline)
                    Text("\(session.orderedSets.count) sets logged").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .padding().frame(maxWidth: .infinity, alignment: .leading)
            .cadenceGlassBackground(
                in: RoundedRectangle(cornerRadius: 18, style: .continuous),
                tint: .green,
                interactive: true,
                fallback: AnyShapeStyle(.green.opacity(0.18)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityIdentifier("home.resume")
    }
}
