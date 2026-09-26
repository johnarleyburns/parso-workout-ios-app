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
        todayHeroCard
        HomeWeekRingsCard(dashboard: dashboard)
        HomeMyWorkoutsSection(
            completed: workoutsTodayRows,
            scheduled: scheduledWorkouts,
            plannedItems: cachedScheduledItems,
            onOpenCompleted: openTodayWorkout,
            onStartScheduled: startScheduledWorkout,
            onShowMorePlanned: { plannedWorkoutsPresented = true })
    }

    private var todayHeroCard: some View {
        let todayScheduled = scheduledWorkouts.first {
            Calendar.current.isDateInToday($0.scheduledDate) && $0.isVisible
        }
        let activeSession = resumeSession
        let scheduledPlan = todayScheduled.flatMap { try? ScheduledWorkoutStore.decode($0.payloadData,
                                                                                         version: $0.payloadVersion) }
        func heroLines(_ plan: EditablePlan?) -> [TodayHero.Line] {
            plan?.exercises.prefix(5).map {
                TodayHero.Line(name: $0.name,
                               detail: "\($0.sets.count) × \($0.sets.first?.targetReps ?? 0)")
            } ?? dashboard.volume.filter(\.isTracked).prefix(3).map {
                TodayHero.Line(name: $0.displayName,
                               detail: "\(WeeklySetProgress.formattedSets($0.sets)) sets")
            }
        }
        let deficits = dashboard.volume.filter { $0.isTracked && $0.sets < 12 }
            .sorted { $0.sets < $1.sets }
            .prefix(2)
            .map { "\($0.displayName.lowercased()) \(WeeklySetProgress.formattedSets($0.sets)) / 12" }
        let reason = deficits.isEmpty ? "Why today: keep your weekly strength habit moving." :
            "Why today: \(deficits.joined(separator: " and ")) sets this week."
        let suggested = TodayHero(kind: .suggested,
                                  title: todaySuggestedPlan?.title ?? "Posterior chain + core",
                                  estimatedMinutes: 45,
                                  exercises: heroLines(todaySuggestedPlan), reason: reason,
                                  citationIDs: SuggestedWorkoutPresenter.citationIDs)
        let scheduled = todayScheduled.map {
            TodayHero(kind: .scheduled, title: $0.title, estimatedMinutes: 45,
                      exercises: heroLines(scheduledPlan), reason: nil)
        }
        let inProgress = activeSession.map {
            TodayHero(kind: .inProgress,
                      title: $0.title.isEmpty ? "Resume your workout" : $0.title,
                      estimatedMinutes: 45, exercises: heroLines(EditablePlan.from(session: $0)),
                      reason: nil)
        }
        let hero = TodayHeroPresenter.hero(inProgress: inProgress, scheduled: scheduled,
                                           suggested: suggested,
                                           completedWorkoutCount: sessions.filter { $0.hasSets && $0.deletedAt == nil }.count)
        let tag: String = switch hero.kind {
        case .inProgress: "In progress"
        case .scheduled: "Scheduled for you"
        case .needsHistory: "Build your history"
        case .restDay: "Recovery day"
        case .suggested: "Suggested for you"
        }
        return HomeTodayHeroCard(title: hero.title, tag: tag,
                                 estimatedMinutes: hero.estimatedMinutes, exercises: hero.exercises.map { (name: $0.name, detail: $0.detail) }, reason: hero.reason,
                                 rationale: todaySuggestedPlan?.recommendationRationale,
                                 citationIDs: hero.citationIDs,
                                 onStart: {
                                     if activeSession != nil {
                                         if let activeSession,
                                            active.strengthSession?.id != activeSession.id {
                                             active.adopt(activeSession, heartbeat: WorkoutHeartbeatStore.read())
                                         }
                                         active.present()
                                     } else if let todayScheduled {
                                         startScheduledWorkout(todayScheduled)
                                     } else {
                                         openTodaySuggestion()
                                     }
                                 },
                                 onEdit: { openTodaySuggestion() },
                                 onChooseAnother: { selectWorkoutPresented = true })
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
