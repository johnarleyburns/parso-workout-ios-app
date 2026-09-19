import SwiftUI
import CadenceCore
import CadenceFeatures

extension HomeView {
    @ViewBuilder
    private var dashboardTopContent: some View {
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
        homeActionRow
        HomeMyWorkoutsSection(
            completed: workoutsTodayRows,
            scheduled: scheduledWorkouts,
            plannedItems: cachedScheduledItems,
            onOpenCompleted: openTodayWorkout,
            onStartScheduled: startScheduledWorkout,
            onShowMorePlanned: { path.append(HomeRoute.plannedWorkouts) })
    }

    private var dashboardWeekContent: some View {
        HomeWeekDashboardSection(
            dashboard: dashboard,
            strengthExpanded: $weeklyStrengthExpanded,
            cardioExpanded: $weeklyCardioExpanded,
            volumeExpanded: $weeklyVolumeExpanded,
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
            onOpenWorkout: openWeekWorkout,
            onOpenCoachSettings: { path.append(HomeRoute.coachPreferences) })
    }

    @ViewBuilder
    private var dashboardBottomContent: some View {
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
