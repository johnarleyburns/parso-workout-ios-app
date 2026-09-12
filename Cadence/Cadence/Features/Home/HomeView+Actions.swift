import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

extension HomeView {
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
    /// Pulls any new Watch/Health-recorded cardio into the local store (FR-2.1).
    /// Formerly auto-run by the now-removed Cardio screen (feedback batch 3).
    func syncCardioFromHealth() async {
        let new = await model.health.newWorkouts(since: model.lastHealthSync)
        let inserted = (try? WorkoutRepository.ingest(new, in: context)) ?? 0
        model.lastHealthSync = Date()
        if inserted > 0 { markWorkoutHistoryChanged() }
    }
    var homeActionRow: some View {
        VStack(spacing: CGFloat(LayoutMetrics.actionButtonSpacing)) {
            CadenceActionButton(title: "Start Workout", systemImage: "play.fill") {
                Haptics.selection()
                if active.liveWorkout.active != nil { showWorkoutConflict = true } else { selectWorkoutPresented = true }
            }
            .accessibilityIdentifier("home.startWorkout")
            CadenceActionButton(title: "Log Previous Workout",
                                systemImage: "square.and.pencil",
                                emphasis: .secondary) {
                Haptics.selection()
                logPickerPresented = true
            }
            .accessibilityIdentifier("home.logWorkout")
        }
    }
    /// Workouts completed today; coach recommendations stay in the coach and
    /// Start Workout surfaces rather than appearing as historical activity.
    var workoutsTodayRows: [WorkoutsTodayPresenter.Row] {
        WorkoutsTodayPresenter.historicalRows(
            sessions: sessions,
            cardio: cardio)
    }
    func openTodayWorkout(_ row: WorkoutsTodayPresenter.Row) {
        guard let id = UUID(uuidString: row.sourceKey) else { return }
        switch row.modality {
        case .strength:
            if let s = sessions.first(where: { $0.id == id }) { path.append(s) }
        case .cardio:
            if let c = cardio.first(where: { $0.id == id }) { path.append(c) }
        }
    }
    /// Captures SwiftData values on the main actor, then lets the sheet run the
    /// pure, Sendable generator without carrying managed objects across actors.
    func requestSuggestedWorkout() {
        Haptics.selection()
        do {
            let persistedCandidates = try SuggestedWorkoutSignposts.exerciseFetchAndMap {
                try WorkoutRepository.allExercises(context).map { exercise in
                    SuggestedExerciseCandidate(
                        id: exercise.sourceExerciseID ?? exercise.id.uuidString,
                        name: exercise.name,
                        mechanics: exercise.mechanicsValue ?? .compound,
                        primaryMuscles: exercise.primaryMuscles,
                        secondaryMuscles: exercise.secondaryMuscles,
                        volumeEligible: exercise.volumeEligible,
                        trainingTypes: exercise.trainingTypes,
                        modalities: exercise.modalities,
                        sportContexts: exercise.sportContexts)
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
            }
            if persistedCatalogIsUsable {
                candidates = persistedCandidates
            } else {
                candidates = ExerciseLibrary.starter.map(SuggestedExerciseCandidate.init(template:))
            }
            let asOf = Date()
            let request = SuggestedWorkoutRequest(
                input: SuggestedWorkoutInput(
                    completedSetsByMuscle: coachFacts.weeklySetsByMuscle,
                    candidates: candidates,
                    trackedGroups: settings.coachSchedulePreferences.trackedMuscleGroups,
                    preferredSetsPerExercise: settings.coachSchedulePreferences.desiredSetsPerExercise,
                    trainingGoal: settings.trainingGoal,
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
            // The chooser renders a recoverable failure state for generator work;
            // a fetch failure has no safe partial candidate snapshot to present.
            suggestedWorkoutRequest = SuggestedWorkoutRequest(
                input: SuggestedWorkoutInput(completedSetsByMuscle: coachFacts.weeklySetsByMuscle,
                                              candidates: [],
                                              trackedGroups: settings.coachSchedulePreferences.trackedMuscleGroups,
                                              preferredSetsPerExercise: settings.coachSchedulePreferences.desiredSetsPerExercise,
                                              trainingGoal: settings.trainingGoal,
                                              engineContext: SuggestedWorkoutEngineContext(
                                                  experience: settings.experienceLevel,
                                                  schedule: settings.coachSchedulePreferences,
                                                  availableEquipment: Equipment.allCases,
                                                  environment: "commercial_gym",
                                                  asOf: Date())),
                unit: settings.unit,
                warmupMinutes: settings.warmupMinutes,
                cooldownMinutes: settings.cooldownMinutes,
                failureMessage: "Exercise data could not be read. Retry to try again.")
        }
    }

    private func presentSuggestedWorkout(_ request: SuggestedWorkoutRequest) {
        if selectWorkoutPresented || weightsStartPresented {
            selectWorkoutPresented = false
            weightsStartPresented = false
            Task { @MainActor in
                await Task.yield()
                suggestedWorkoutRequest = request
            }
        } else {
            suggestedWorkoutRequest = request
        }
    }

    /// Quiet trial status shown above the Coach card while on the free trial.
    func trialBanner(daysLeft: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "gift.fill").font(.caption)
            Text("Trial — \(daysLeft) day\(daysLeft == 1 ? "" : "s") left")
                .font(.caption.weight(.medium))
            Spacer()
        }
        .foregroundStyle(.green)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(.green.opacity(0.10), in: Capsule())
        .accessibilityIdentifier("coach.trialBanner")
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
                    path.append(HomeRoute.yourPlan)
                }
            }
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.weekStrip")
    }

    var homeFavoriteRoutines: [WorkoutPlan] {
        settings.favoriteRoutineIDs.compactMap { PlanCatalog.plan(forKey: $0) }
            .sorted { $0.name < $1.name }
    }

    @ViewBuilder
    var favoritesSection: some View {
        let routines = homeFavoriteRoutines
        if !routines.isEmpty || !favoriteExercises.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("Favorites", systemImage: "heart.fill")
                    .font(.headline).foregroundStyle(.pink)
                if !routines.isEmpty {
                    Text("Routines").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(routines) { plan in
                        NavigationLink {
                            RoutineDetailView(plan: plan, onEditorStart: { plan in handleEditorStart(plan); path = NavigationPath() })
                        } label: {
                            HStack {
                                Text(plan.name).font(.subheadline)
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                if !favoriteExercises.isEmpty {
                    Text("Exercises").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        .padding(.top, routines.isEmpty ? 0 : 4)
                    ForEach(favoriteExercises) { ex in
                        NavigationLink {
                            ExerciseDetailView(exercise: ex)
                        } label: {
                            HStack {
                                Text(ex.name).font(.subheadline)
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .cadenceGlassCard(in: CadenceCardShape.rounded, tint: .pink)
        }
    }

    var weekActivity: (strength: [TodayActivityPresenter.Entry], cardio: [TodayActivityPresenter.Entry]) {
        _ = historyRefreshToken
        return TodayActivityPresenter.weekEntries(sessions: sessions, cardio: cardio)
    }
    func openWeekWorkout(_ entry: TodayActivityPresenter.Entry) {
        switch entry.kind {
        case .strength:
            if let s = sessions.first(where: { $0.id == entry.sourceId }) { path.append(s) }
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
