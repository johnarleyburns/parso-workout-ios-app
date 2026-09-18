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
                CadenceActionButton(title: "Schedule Workout",
                                    systemImage: "calendar.badge.plus",
                                    emphasis: .secondary) {
                    Haptics.selection()
                    path.append(HomeRoute.workoutEditor(
                        .empty(warmup: settings.warmupMinutes,
                               cooldown: settings.cooldownMinutes)))
                }
                .accessibilityIdentifier("home.scheduleWorkout")

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

    var recentCardioTypes: [WorkoutType] {
        cachedRecentCardioTypes
    }

    /// Rebuilds historical display projections once per refresh rather than once
    /// for every SwiftUI body evaluation. The model relationships are read from
    /// a background context so a Home refresh cannot fault a large history graph
    /// on the main actor. Active set-entry changes do not alter these rows;
    /// completion and edits bump `historyRefreshToken`.
    func refreshHomeActivitySnapshot() async {
        let signpostID = OSSignpostID(log: Self.healthIngestLog)
        os_signpost(.begin, log: Self.healthIngestLog, name: "homeActivityProjection", signpostID: signpostID)
        defer { os_signpost(.end, log: Self.healthIngestLog, name: "homeActivityProjection", signpostID: signpostID) }
        let now = Date()
        if let container = cadenceModelContainer {
            let projection = await Task.detached(priority: .utility) { [container, now] in
                let backgroundContext = ModelContext(container)
                let sessions = (try? WorkoutRepository.allSessions(backgroundContext)) ?? []
                let cardio = (try? WorkoutRepository.allCardio(backgroundContext)) ?? []
                let scheduled = (try? backgroundContext.fetch(FetchDescriptor<ScheduledWorkout>(
                    sortBy: [SortDescriptor(\ScheduledWorkout.scheduledDate),
                             SortDescriptor(\ScheduledWorkout.title)]))) ?? []
                var recentCardioTypes: [WorkoutType] = []
                for workout in cardio
                    .filter({ $0.deletedAt == nil })
                    .sorted(by: { $0.start > $1.start }) {
                    let type: WorkoutType?
                    switch workout.typeValue {
                    case .run: type = .run
                    case .walk: type = .walk
                    case .cycle: type = .cycle
                    case .rowing: type = .rowing
                    case .swim: type = .swim
                    case .elliptical: type = .elliptical
                    case .stairClimber: type = .stairClimber
                    case .hiit: type = .hiit
                    case .boxing: type = .boxing
                    case .other: type = nil
                    }
                    if let type, !recentCardioTypes.contains(type) {
                        recentCardioTypes.append(type)
                    }
                }
                let week = TodayActivityPresenter.weekEntries(sessions: sessions, cardio: cardio, now: now)
                return HomeActivityProjection(
                    today: WorkoutsTodayPresenter.historicalRows(
                        sessions: sessions, cardio: cardio, now: now),
                    weekStrength: week.strength,
                    weekCardio: week.cardio,
                    weeklyVolumeKg: WeeklyStats.volumeKg(
                        sessions.filter { $0.deletedAt == nil },
                        since: WeeklyStats.weekStart(now: now)),
                    muscleHistory: HomeMuscleHistoryPresenter.make(
                        sessions: sessions,
                        since: WeeklyStats.weekStart(now: now),
                        now: now),
                    scheduledItems: scheduled.map(HomePlannedWorkoutsSection.rowInput)
                        .map(HomePlannedWorkoutsSection.item),
                    recentCardioTypes: recentCardioTypes)
            }.value
            guard !Task.isCancelled else { return }
            cachedWorkoutsTodayRows = projection.today
            cachedWeekStrengthEntries = projection.weekStrength
            cachedWeekCardioEntries = projection.weekCardio
            cachedWeeklyVolumeKg = projection.weeklyVolumeKg
            cachedMuscleHistory = projection.muscleHistory
            cachedScheduledItems = projection.scheduledItems
            cachedRecentCardioTypes = projection.recentCardioTypes
        } else {
            cachedWorkoutsTodayRows = WorkoutsTodayPresenter.historicalRows(
                sessions: sessions, cardio: cardio, now: now)
            let week = TodayActivityPresenter.weekEntries(sessions: sessions, cardio: cardio, now: now)
            cachedWeekStrengthEntries = week.strength
            cachedWeekCardioEntries = week.cardio
            cachedWeeklyVolumeKg = WeeklyStats.volumeKg(
                sessions.filter { $0.deletedAt == nil },
                since: WeeklyStats.weekStart(now: now))
            cachedMuscleHistory = HomeMuscleHistoryPresenter.make(
                sessions: sessions,
                since: WeeklyStats.weekStart(now: now),
                now: now)
            cachedScheduledItems = scheduledWorkouts.map(HomePlannedWorkoutsSection.item)
            cachedRecentCardioTypes = recentCardioTypesFromCurrentCardio
        }
    }

    private var recentCardioTypesFromCurrentCardio: [WorkoutType] {
        var result: [WorkoutType] = []
        for workout in cardio
            .filter({ $0.deletedAt == nil })
            .sorted(by: { $0.start > $1.start }) {
            let type: WorkoutType?
            switch workout.typeValue {
            case .run: type = .run
            case .walk: type = .walk
            case .cycle: type = .cycle
            case .rowing: type = .rowing
            case .swim: type = .swim
            case .elliptical: type = .elliptical
            case .stairClimber: type = .stairClimber
            case .hiit: type = .hiit
            case .boxing: type = .boxing
            case .other: type = nil
            }
            if let type, !result.contains(type) { result.append(type) }
        }
        return result
    }

    private struct HomeActivityProjection: @unchecked Sendable {
        let today: [WorkoutsTodayPresenter.Row]
        let weekStrength: [TodayActivityPresenter.Entry]
        let weekCardio: [TodayActivityPresenter.Entry]
        let weeklyVolumeKg: Double
        let muscleHistory: [HomeMuscleHistory]
        let scheduledItems: [PlannedWorkoutsPresenter.Item]
        let recentCardioTypes: [WorkoutType]
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
    var homeWeekHistoryEntries: [TodayActivityPresenter.Entry] {
        (cachedWeekStrengthEntries + cachedWeekCardioEntries)
            .sorted { $0.occurredAt > $1.occurredAt }
    }
    var homeReadinessTitle: String {
        todayReadiness == nil ? "Readiness" : "Today's readiness"
    }
    var homeReadinessSubtitle: String {
        guard let todayReadiness else { return "Optional check-in" }
        return ReadinessCheckInPresenter.summary(for: todayReadiness)
    }
    var suggestedWorkoutFailurePresented: Binding<Bool> {
        Binding(
            get: { suggestedWorkoutFailure != nil },
            set: { if !$0 { suggestedWorkoutFailure = nil } })
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
