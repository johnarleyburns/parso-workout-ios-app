import SwiftUI
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures

extension HomeView {

    @ViewBuilder
    var dashboardTopContent: some View {
        WeeklyIntentRingsCard(
            display: WeeklyIntentPresenter.make(strength: dashboard.strength, cardio: dashboard.cardio),
            tabSelection: rootTabSelection)
        if resumeSession != nil {
            todayHeroCard
        }
    }

    var workoutStartControls: some View {
        HomeWorkoutStartControls(
            onQuickStart: { startQuickStartStrength() },
            onSuggested: { openTodaySuggestion() },
            onPreviousStart: handleEditorStart,
            onCardio: { start($0) },
            onCustomCardio: { startOtherCardio(description: $0, gps: $1) })
    }

    /// Rows for the compact dual card; empty keeps the existing hero. Only the
    /// normal generated recommendation is replaced: loading, in-progress,
    /// scheduled, recovery/pain, and completed-day states keep the hero.

    private var todayHeroCard: some View {
        Group {
            if let session = resumeSession {
                VStack(alignment: .leading, spacing: 8) {
                    Text("In progress").font(.subheadline).foregroundStyle(.secondary)
                    Text(session.title.isEmpty ? String(localized: "Workout") : session.title)
                        .font(.headline)
                    Button {
                        if active.strengthSession?.id != session.id {
                            active.adopt(session, heartbeat: WorkoutHeartbeatStore.read())
                        }
                        active.present()
                    } label: {
                        Label("Resume workout", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .font(.headline)
                    .cadenceGlassButton(prominent: true, tint: CadenceTheme.accent)
                    .accessibilityIdentifier("home.resumeStrength")
                }
            }
        }
    }

    var dashboardStrengthContent: some View {
        HomeWeekDashboardSection(
            dashboard: dashboard,
            scope: .strength,
            detailSelection: $weeklyDetailSelection,
            muscleMapPanel: $weeklyMuscleMapPanel,
            plannedItems: ThisWeekWorkoutsPresenter.plannedThisWeek(cachedScheduledItems),
            inProgressSessions: ThisWeekWorkoutsPresenter.inProgressThisWeek(sessions: sessions),
            completedEntries: homeWeekHistoryEntries,
            muscleHistory: cachedMuscleHistory,
            muscleHistoryByPerformer: cachedMuscleHistoryByPerformer,
            weeklyVolumeByPerformer: cachedWeeklyVolumeByPerformer,
            weeklyVolumeKgByPerformer: cachedWeeklyVolumeKgByPerformer,
            weeklyVolumePerformers: cachedWeeklyVolumePerformers,
            totalVolumeKg: weeklyVolumeKg,
            // The restored recommendation already carries last-known weekly
            // sets. Render those rows immediately and replace their values
            // when the full projection lands; never block the Sets surface on
            // unrelated coach/HealthKit work.
            isVolumeLoading: false,
            unit: settings.unit,
            onOpenWorkout: openWeekWorkout,
            onOpenPlanned: { path.append(HomeRoute.plannedWorkoutDetail($0)) },
            onResumeWorkout: resumeWeekSession,
            onStartWorkout: { session in
                _ = active.startStrength(session)
            },
            onPlanWorkout: { plan in
                workoutEditorPlan = plan
            },
            onSuggestCardio: requestSuggestedCardio,
            onShowHistory: { path.append(HomeRoute.history) })
    }

    var dashboardCardioContent: some View {
        HomeWeekDashboardSection(
            dashboard: dashboard,
            scope: .cardio,
            detailSelection: $weeklyDetailSelection,
            muscleMapPanel: $weeklyMuscleMapPanel,
            plannedItems: [],
            inProgressSessions: [],
            completedEntries: [],
            muscleHistory: [],
            muscleHistoryByPerformer: [:],
            weeklyVolumeByPerformer: [:],
            weeklyVolumeKgByPerformer: [:],
            weeklyVolumePerformers: [],
            totalVolumeKg: 0,
            unit: settings.unit,
            onOpenWorkout: { _ in },
            onOpenPlanned: { _ in },
            onResumeWorkout: { _ in },
            onStartWorkout: { _ in },
            onPlanWorkout: { _ in },
            onSuggestCardio: requestSuggestedCardio,
            onShowHistory: { })
    }

    @ViewBuilder
    var thisWeekContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            switch surface {
            case .strength:
                dashboardStrengthContent
            case .cardio:
                dashboardCardioContent
            case .today:
                EmptyView()
            }
        }
    }
}
