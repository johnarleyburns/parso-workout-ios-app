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
               cardioTarget: dashboard.cardioDetail.targetMinutes) {
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
        HomeWeekRingsCard(
            dashboard: dashboard,
            summary: ThisWeekWorkoutsPresenter.summary(
                planned: ThisWeekWorkoutsPresenter.plannedThisWeek(cachedScheduledItems).count,
                done: cachedWeekStrengthEntries.count + cachedWeekCardioEntries.count),
            isStrengthLoading: !coachSnapshotReady)
    }

    private var todayHeroCard: some View {
        // Value snapshot published by the background activity projection;
        // this render path never touches historical SwiftData rows.
        let activity = cachedTodayHeroActivity
        let activeSession = resumeSession
        func heroLines(_ plan: EditablePlan?) -> [TodayHero.Line] {
            TodayHeroActivityPresenter.heroLines(plan)
        }
        let deficits = dashboard.volume.filter { $0.isTracked && $0.sets < 12 }
            .sorted { $0.sets < $1.sets }
            .prefix(2)
            .map { String(localized: "\($0.displayName) \(WeeklySetProgress.formattedSets($0.sets)) / 12") }
        let reason = deficits.isEmpty ? String(localized: "Why today: keep your weekly strength habit moving.") :
            String(localized: "Why today: \(deficits.formatted(.list(type: .and))) sets this week.")
        // A durable restore renders the hero before the snapshot hydrates.
        // Until history has projected, only a restored recommendation may
        // render; otherwise the hero stays "loading" (never a false recovery
        // or onboarding state).
        let recommendationReady = activity.isLoaded
            ? (coachSnapshotReady || restoredRecommendation != nil)
            : restoredRecommendation != nil
        let coachRecommendsStrength = coachSnapshotReady
            ? coachDecision.primary.kind == .strength
            : (restoredRecommendation?.primaryIsStrength ?? false)
        let suggested = coachRecommendsStrength ? todaySuggestedPlan.map { plan in
            TodayHero(kind: .suggested, title: plan.title,
                      estimatedMinutes: activity.suggestedDurationMinutes(plan: plan),
                      exercises: heroLines(plan), reason: reason,
                      citationIDs: SuggestedWorkoutPresenter.citationIDs)
        } : nil
        let starter = todaySuggestedPlan.map { plan in
            TodayHero(kind: .starter, title: plan.title,
                      estimatedMinutes: activity.suggestedDurationMinutes(plan: plan),
                      exercises: heroLines(plan),
                      reason: String(localized: "A general starter workout to get your first session going. It personalizes once you've logged a couple of workouts."),
                      citationIDs: SuggestedWorkoutPresenter.citationIDs)
        }
        // The personalized generator is intentionally asynchronous and may
        // briefly have no result while the Home card is already rendering.
        // Falling straight through to "Recovery day" made the same Today
        // recommendation appear to flip between strength and recovery based on
        // launch timing. The already-computed Coach decision is the stable
        // fallback until the personalized plan arrives (or if generation has
        // no launchable catalog result).
        let coachFallback = coachSnapshotReady
            ? TodayHeroPresenter.recommendation(coachDecision)
            : restoredRecommendation?.makeHero()
        let scheduled = activity.todayScheduled?.makeHero()
        let inProgress = activeSession.map { session -> TodayHero in
            let progress = InProgressWorkoutPresenter.progress(session: session)
            return TodayHero(kind: .inProgress,
                             title: session.title.isEmpty ? String(localized: "Resume your workout") : session.title,
                             exercises: progress.lines,
                             reason: InProgressWorkoutPresenter.summary(progress))
        }
        let hero = TodayHeroPresenter.hero(inProgress: inProgress, scheduled: scheduled,
                                           suggested: suggested,
                                           fallbackRecommendation: coachFallback,
                                           starter: starter,
                                           // Unloaded history must not read as "no history".
                                           completedWorkoutCount: activity.isLoaded ? activity.completedWorkoutCount : max(2, activity.completedWorkoutCount),
                                           completedToday: activity.daySummary(),
                                           remainingScheduledToday: activity.remainingScheduledToday,
                                           recommendationReady: recommendationReady)
        let tag: String = switch hero.kind {
        case .inProgress: String(localized: "In progress")
        case .scheduled: String(localized: "Scheduled for you")
        case .doneToday: String(localized: "Done for today")
        case .needsHistory: String(localized: "Build your history")
        case .restDay: String(localized: "Recovery day")
        case .suggested: String(localized: "Suggested for you")
        case .starter: String(localized: "Starter workout")
        case .loading: String(localized: "Loading")
        }
        let showingSuggestedPlan = todaySuggestedPlan != nil && (coachRecommendsStrength || hero.kind == .starter)
        let heroCard = HomeTodayHeroCard(title: hero.title, tag: tag,
                                 estimatedMinutes: hero.estimatedMinutes, exercises: hero.exercises.map { (name: $0.name, detail: $0.detail) }, reason: hero.reason,
                                 rationale: showingSuggestedPlan
                                    ? todaySuggestedPlan?.recommendationRationale
                                    : hero.reason.map { SuggestedWorkoutRationale(whyWorkout: $0, exercises: []) },
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
                                     } else if activity.todayScheduled != nil, startTodayScheduledWorkout() {
                                         // Started the scheduled plan.
                                     } else if showingSuggestedPlan {
                                         openTodaySuggestion()
                                     } else {
                                         launchDecision(coachDecision.primary)
                                     }
                                 },
                                 onShowAllExercises: { if showingSuggestedPlan { openTodaySuggestion() } else { launchDecision(coachDecision.primary) } },
                                 onEdit: { if showingSuggestedPlan { openTodaySuggestion() } else { launchDecision(coachDecision.primary) } },
                                 onChooseAnother: { if hero.kind == .restDay { recoveryOptionsPresented = true } else { selectWorkoutPresented = true } },
                                 onViewSummary: {
                                     if let row = workoutsTodayRows.first(where: { $0.modality == .strength }) {
                                         openTodayWorkout(row)
                                     }
                                 },
                                 onAddSomething: { selectWorkoutPresented = true })
        return VStack(alignment: .leading, spacing: 8) {
            heroCard
            if let pending = pendingSuggestedWorkoutPlan,
               hero.kind == .suggested || hero.kind == .starter || hero.kind == .restDay {
                HStack(spacing: 12) {
                    Label("Created a new workout for today", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Button("Show it") {
                        todaySuggestedPlan = pending
                        pendingSuggestedWorkoutPlan = nil
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    Button("Not now") {
                        pendingSuggestedWorkoutPlan = nil
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Created a new workout for today. Show it, or dismiss to keep your current suggestion.")
                .accessibilityIdentifier("home.hero.newSuggestionBanner")
            }
        }
    }

    var dashboardWeekContent: some View {
        HomeWeekDashboardSection(
            dashboard: dashboard,
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
            isVolumeLoading: !(coachSnapshotReady && dashboardActivityReady),
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
            onShowHistory: { path.append(HomeRoute.history) })
    }

    @ViewBuilder
    var dashboardBottomContent: some View {
        HomeCoachSuggestionsSection(
            suggestions: dashboard.suggestions,
            focusGroup: dashboard.volume.first(where: { $0.isTracked && $0.sets < 12 })?.group ?? .chest,
            expanded: $suggestionsExpanded)
        homeDetailDisclosure(
            title: homeReadinessTitle,
            subtitle: homeReadinessSubtitle,
            expanded: $readinessExpanded,
            identifier: "home.readiness.show")
        if readinessExpanded { readinessCard }
    }
}
