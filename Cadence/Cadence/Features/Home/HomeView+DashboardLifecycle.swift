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
            .onReceive(NotificationCenter.default.publisher(for: .readinessCheckInChanged)) { _ in
                markWorkoutHistoryChanged()
            }
            .onReceive(NotificationCenter.default.publisher(for: .cadenceStartTodaysWorkout)) { _ in
                guard active.liveWorkout.active == nil else { return }
                selectWorkoutPresented = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .cadenceShowTodaysPlan)) { _ in
                path.append(HomeRoute.yourPlan)
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
