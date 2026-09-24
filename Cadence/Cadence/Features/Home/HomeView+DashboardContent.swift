import SwiftUI
import CadenceCore
import CadenceFeatures

extension HomeView {
    @ViewBuilder
    var dashboardTopContent: some View {
        HStack {
            Text(headerDateText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("home.headerDate")
            Spacer(minLength: 8)
            if contributions.store.isSupporter {
                Label("Supporter", systemImage: "heart.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.pink)
                    .accessibilityIdentifier("home.supporterBadge")
            }
        }
        if let s = resumeSession { resumeCard(s) }
        SelectWorkoutView(
            onSuggestedWorkout: { requestSuggestedWorkout($0) },
            onEditorStart: {
                path = NavigationPath()
                handleEditorStart($0)
            },
            onScheduleStrength: {
                path = NavigationPath()
                workoutEditorPlan = .empty(warmup: settings.warmupMinutes,
                                            cooldown: settings.cooldownMinutes)
            },
            onLogWorkout: {
                path = NavigationPath()
                logPickerPresented = true
            },
            onStartCardio: {
                path = NavigationPath()
                start($0)
            },
            onScheduleCardio: {
                path = NavigationPath()
                scheduleCardioType = $0
            },
            onOtherCardio: { description, gps in
                path = NavigationPath()
                startOtherCardio(description: description, gps: gps)
            },
            recentCardioTypes: recentCardioTypes,
            inline: true)
        HomeMyWorkoutsSection(
            completed: workoutsTodayRows,
            scheduled: scheduledWorkouts,
            plannedItems: cachedScheduledItems,
            onOpenCompleted: openTodayWorkout,
            onStartScheduled: startScheduledWorkout,
            onShowMorePlanned: { plannedWorkoutsPresented = true })
    }

    var dashboardWeekContent: some View {
        HomeWeekDashboardSection(
            dashboard: dashboard,
            detailSelection: $weeklyDetailSelection,
            muscleMapPanel: $weeklyMuscleMapPanel,
            strengthEntries: weekActivity.strength,
            cardioEntries: weekActivity.cardio,
            muscleHistory: cachedMuscleHistory,
            muscleHistoryByPerformer: cachedMuscleHistoryByPerformer,
            weeklyVolumeByPerformer: cachedWeeklyVolumeByPerformer,
            weeklyVolumeKgByPerformer: cachedWeeklyVolumeKgByPerformer,
            weeklyVolumePerformers: cachedWeeklyVolumePerformers,
            totalVolumeKg: weeklyVolumeKg,
            unit: settings.unit,
            onOpenWorkout: openWeekWorkout)
    }

    @ViewBuilder
    var dashboardBottomContent: some View {
        homeDetailDisclosure(
            title: "Observations",
            subtitle: dashboard.suggestions.isEmpty ? "No new suggestions" : "Coach guidance and rationale",
            expanded: $observationsExpanded,
            identifier: "home.observations.show")
        if observationsExpanded {
            HomeCoachSuggestionsSection(
                suggestions: dashboard.suggestions,
                illustration: coachIllustration,
                expanded: $suggestionsExpanded)
        }
        homeDetailDisclosure(
            title: homeReadinessTitle,
            subtitle: homeReadinessSubtitle,
            expanded: $readinessExpanded,
            identifier: "home.readiness.show")
        if readinessExpanded { readinessCard }
    }
}
