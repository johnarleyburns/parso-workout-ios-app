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
        if surface == .thisWeek,
           let close = WeekCloseMoment.make(
               workingSets: dashboard.volumeCoverage.completed,
               setTarget: dashboard.volumeCoverage.target,
               cardioMinutes: dashboard.cardioDetail.moderateEquivalentMinutes,
               cardioTarget: dashboard.cardioDetail.targetMinutes,
               sessions: dashboard.strength.completed,
               sessionTarget: dashboard.strength.target) {
            VStack(alignment: .leading, spacing: 4) {
                Label(close.title, systemImage: "party.popper.fill")
                    .font(.headline)
                    .foregroundStyle(CadenceTheme.achievement)
                Text(close.detail).font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CadenceTheme.achievement.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .sensoryFeedback(.success, trigger: close.title)
            .accessibilityIdentifier("week.closeMoment")
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
            } ?? []
        }
        let deficits = dashboard.volume.filter { $0.isTracked && $0.sets < 12 }
            .sorted { $0.sets < $1.sets }
            .prefix(2)
            .map { String(localized: "\($0.displayName) \(WeeklySetProgress.formattedSets($0.sets)) / 12") }
        let reason = deficits.isEmpty ? String(localized: "Why today: keep your weekly strength habit moving.") :
            String(localized: "Why today: \(deficits.formatted(.list(type: .and))) sets this week.")
        let coachRecommendsStrength = coachSnapshotReady && coachDecision.primary.kind == .strength
        let suggested = coachRecommendsStrength ? todaySuggestedPlan.map { plan in
            TodayHero(kind: .suggested, title: plan.title,
                      estimatedMinutes: WorkoutDurationEstimator.estimate(
                          plan: plan, history: sessions)?.minutes,
                      exercises: heroLines(plan), reason: reason,
                      citationIDs: SuggestedWorkoutPresenter.citationIDs)
        } : nil
        // The personalized generator is intentionally asynchronous and may
        // briefly have no result while the Home card is already rendering.
        // Falling straight through to "Recovery day" made the same Today
        // recommendation appear to flip between strength and recovery based on
        // launch timing. The already-computed Coach decision is the stable
        // fallback until the personalized plan arrives (or if generation has
        // no launchable catalog result).
        let coachFallback: TodayHero? = {
            let session = coachDecision.primary
            guard coachRecommendsStrength else { return nil }
            let lines = (session.exercises ?? []).prefix(5).map { exercise in
                let reps: String
                if let low = exercise.repsLow, let high = exercise.repsHigh, low != high {
                    reps = "\(low)–\(high)"
                } else if let repsLow = exercise.repsLow {
                    reps = "\(repsLow)"
                } else {
                    reps = "—"
                }
                let sets = exercise.sets.map(String.init) ?? "—"
                return TodayHero.Line(name: exercise.name, detail: "\(sets) × \(reps)")
            }
            return TodayHero(kind: .suggested,
                             title: session.title,
                             estimatedMinutes: session.durationMinutes,
                             exercises: Array(lines),
                             reason: session.subtitle.isEmpty ? reason : String(localized: "Why today: \(session.subtitle)"),
                             citationIDs: session.citationIds)
        }()
        let scheduled = todayScheduled.map {
            TodayHero(kind: .scheduled, title: $0.title,
                      estimatedMinutes: WorkoutDurationEstimator.estimate(
                          plan: scheduledPlan, history: sessions)?.minutes,
                      exercises: heroLines(scheduledPlan), reason: nil)
        }
        let inProgress = activeSession.map {
            TodayHero(kind: .inProgress,
                      title: $0.title.isEmpty ? String(localized: "Resume your workout") : $0.title,
                      estimatedMinutes: Int(max(0, $0.duration) / 60),
                      exercises: heroLines(EditablePlan.from(session: $0)),
                      reason: nil)
        }
        let today = Calendar.current.startOfDay(for: Date())
        let completedToday = sessions
            .filter { session in
                session.deletedAt == nil && session.endedAt != nil && session.hasSets
                    && Calendar.current.isDate(session.endedAt ?? session.date, inSameDayAs: today)
            }
            .sorted { ($0.endedAt ?? $0.date) > ($1.endedAt ?? $1.date) }
            .first
        let nextScheduled = scheduledWorkouts
            .filter { $0.isVisible && $0.scheduledDate >= today && !Calendar.current.isDateInToday($0.scheduledDate) }
            .sorted { $0.scheduledDate < $1.scheduledDate }
            .first
        let completedSummary = completedToday.map {
            DaySummary(title: $0.title.isEmpty ? String(localized: "Workout complete") : $0.title,
                       setCount: $0.orderedSets.filter { !$0.isWarmup && $0.isOwnerSet }.count,
                       volumeKg: $0.totalVolume,
                       durationMinutes: $0.duration > 0 ? Int(($0.duration / 60).rounded()) : nil,
                       nextSessionTitle: nextScheduled?.title,
                       nextSessionDate: nextScheduled?.scheduledDate)
        }
        let remainingScheduledToday = scheduledWorkouts.filter {
            Calendar.current.isDateInToday($0.scheduledDate) && $0.isVisible
        }.count
        let hero = TodayHeroPresenter.hero(inProgress: inProgress, scheduled: scheduled,
                                           suggested: suggested,
                                           fallbackRecommendation: coachFallback,
                                           completedWorkoutCount: sessions.filter { $0.hasSets && $0.deletedAt == nil }.count,
                                           completedToday: completedSummary,
                                           remainingScheduledToday: remainingScheduledToday,
                                           recommendationReady: coachSnapshotReady)
        let tag: String = switch hero.kind {
        case .inProgress: String(localized: "In progress")
        case .scheduled: String(localized: "Scheduled for you")
        case .doneToday: String(localized: "Done for today")
        case .needsHistory: String(localized: "Build your history")
        case .restDay: String(localized: "Recovery day")
        case .suggested: String(localized: "Suggested for you")
        case .loading: String(localized: "Loading")
        }
        return HomeTodayHeroCard(title: hero.title, tag: tag,
                                 estimatedMinutes: hero.estimatedMinutes, exercises: hero.exercises.map { (name: $0.name, detail: $0.detail) }, reason: hero.reason,
                                 rationale: todaySuggestedPlan?.recommendationRationale,
                                 citationIDs: hero.citationIDs,
                                 summary: hero.summary,
                                 unit: settings.unit,
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
                                 onChooseAnother: { selectWorkoutPresented = true },
                                 onViewSummary: {
                                     if let row = workoutsTodayRows.first(where: { $0.modality == .strength }) {
                                         openTodayWorkout(row)
                                     }
                                 },
                                 onAddSomething: { selectWorkoutPresented = true })
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
            title: String(localized: "Observations"),
            subtitle: dashboard.suggestions.isEmpty ? String(localized: "No new suggestions") : String(localized: "Coach guidance and rationale"),
            expanded: $observationsExpanded,
            identifier: "home.observations.show")
        if observationsExpanded {
            HomeCoachSuggestionsSection(
                suggestions: dashboard.suggestions,
                focusGroup: dashboard.volume.first(where: { $0.isTracked && $0.sets < 12 })?.group ?? .chest,
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
