import SwiftUI
import CadenceCore
import CadenceFeatures

extension HomeView {
    var body: some View {
        dashboardContent
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                let today = Self.dayString()
                if settings.lastCoachComputeDay != today {
                    settings.lastCoachComputeDay = today
                    historyRefreshToken = UUID()
                }
                if contributionPromptAllowed { contributions.evaluate() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .workoutHistoryChanged)) { _ in
                // A past workout's date was edited (SessionView). The coach signature
                // keys on counts + token, not per-session dates, so bump the token to
                // recompute the snapshot / "This Week" strip without an app relaunch.
                markWorkoutHistoryChanged()
            }
            .onReceive(NotificationCenter.default.publisher(for: .workoutVolumeChanged)) { note in
                let now = Date()
                guard let change = note.object as? WorkoutVolumeChange,
                      change.date >= WeeklyStats.weekStart(now: now),
                      change.date <= now
                else { return }
                for (group, delta) in change.delta {
                    liveVolumeDelta[group, default: 0] += delta
                }
                cachedDashboard = makeDashboard()
            }
            .onReceive(NotificationCenter.default.publisher(for: .readinessCheckInChanged)) { _ in
                markWorkoutHistoryChanged()
            }
            .onReceive(NotificationCenter.default.publisher(for: .scheduledWorkoutCreated)) { _ in
                // A schedule can be created from a nested Workout Plan inside
                // the start sheet. Clear every Home-owned presentation layer
                // so the user always lands back on Home after saving.
                path = NavigationPath()
                selectWorkoutPresented = false
                weightsStartPresented = false
                scheduleCardioType = nil
                scheduledWorkoutBeingStarted = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: .scheduledWorkoutStartRequested)) { note in
                guard let request = note.object as? ScheduledWorkoutStartRequest else { return }
                path = NavigationPath()
                selectWorkoutPresented = false
                weightsStartPresented = false
                consumeScheduledWorkoutStart(request)
            }
            .onReceive(NotificationCenter.default.publisher(for: .scheduledCardioStartRequested)) { note in
                guard let request = note.object as? ScheduledCardioStartRequest else { return }
                guard active.liveWorkout.active == nil else {
                    showWorkoutConflict = true
                    return
                }
                path = NavigationPath()
                selectWorkoutPresented = false
                weightsStartPresented = false
                start(WorkoutType(rawValue: request.type.rawValue) ?? .other)
            }
            .onReceive(NotificationCenter.default.publisher(for: .cadenceStartTodaysWorkout)) { _ in
                guard active.liveWorkout.active == nil else { return }
                selectWorkoutPresented = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .cadenceShowTodaysPlan)) { _ in
                path.append(HomeRoute.plannedWorkouts)
            }
            .onChange(of: active.finishedSummary != nil) { _, shown in
                if shown {
                    ContributionCoordinator.recordWorkoutCompleted()
                    // A strength workout just finished — refresh the (decoupled) coach
                    // snapshot so Home reflects it when the user returns.
                    markWorkoutHistoryChanged()
                }
            }
            // Recompute the coach pipeline off the render/tap path, only when history
            // or coach-relevant settings actually change.
            .task(id: HomeCoachTaskIdentity(
                signature: coachSignature,
                isRestoringCloudKitHistory: model.isRestoringCloudKitHistory)) {
                await refreshCoachSnapshot()
            }
            .task(id: HomeActivityTaskIdentity(
                historyRefreshToken: historyRefreshToken,
                sessionCount: sessions.count,
                cardioCount: cardio.count,
                scheduledWorkouts: scheduledWorkouts.map {
                    ScheduledWorkoutTaskSignature(id: $0.id,
                                                  scheduledDate: $0.scheduledDate,
                                                  updatedAt: $0.updatedAt,
                                                  statusRaw: $0.statusRaw,
                                                  payloadVersion: $0.payloadVersion)
                })) {
                // Let the first interactive frame render before walking the
                // historical SwiftData relationships for these compact rows.
                await Task.yield()
                await refreshHomeActivitySnapshot()
            }
            // Passive HealthKit samples arrive asynchronously after the initial
            // pipeline run; rebuild the snapshot whenever they change.
            .onChange(of: passiveSamples) {
                Task { await refreshCoachSnapshot() }
            }
            .coachOverrideConfirmation(
                pending: $pendingAddGapsDeficits,
                guardrails: { CoachOverrideGuardrails.describe(from: coachSnapshot.optimizedPlan.diagnostics) },
                onConfirm: { confirmAddGaps() })
    }
}
