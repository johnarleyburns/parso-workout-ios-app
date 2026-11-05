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
        if coachSnapshotReady, coachDecision.todayPlannedRecommendations.count > 1 {
            todayDualPlanCard
        }
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
        // A recommendation that was rendered from the same-day display cache
        // is a promise to the person looking at Home. Hydration can update
        // internal Coach state, but must not silently exchange its modality or
        // workout beneath them. A later interaction or a new day may choose a
        // new recommendation deliberately.
        let pinnedRecommendation = restoredRecommendation
        let recommendationReady = activity.isLoaded
            ? (coachSnapshotReady || restoredRecommendation != nil)
            : restoredRecommendation != nil
        let coachRecommendsStrength = pinnedRecommendation?.primaryIsStrength ?? (coachSnapshotReady
            ? coachDecision.primary.kind == .strength
            : false)
        let suggested = coachRecommendsStrength ? todaySuggestedPlan.map { plan in
            TodayHero(kind: .suggested, title: plan.title,
                      estimatedMinutes: activity.suggestedDurationMinutes(plan: plan),
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
        let coachFallback = pinnedRecommendation?.makeHero() ?? (coachSnapshotReady
            ? TodayHeroPresenter.recommendation(coachDecision)
            : nil)
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
        case .loading: String(localized: "Loading")
        }
        return HomeTodayHeroCard(title: hero.title, tag: tag,
                                 estimatedMinutes: hero.estimatedMinutes, exercises: hero.exercises.map { (name: $0.name, detail: $0.detail) }, reason: hero.reason,
                                 rationale: hero.kind == .suggested && coachRecommendsStrength && suggested != nil
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
                                     } else if coachRecommendsStrength && todaySuggestedPlan != nil {
                                         openTodaySuggestion()
                                     } else {
                                         launchDecision(coachDecision.primary)
                                     }
                                 },
                                 onShowAllExercises: { if coachRecommendsStrength { openTodaySuggestion() } else { launchDecision(coachDecision.primary) } },
                                 onEdit: { if coachRecommendsStrength { openTodaySuggestion() } else { launchDecision(coachDecision.primary) } },
                                 onChooseAnother: { if hero.kind == .restDay { recoveryOptionsPresented = true } else { selectWorkoutPresented = true } },
                                 onViewSummary: {
                                     path.append(HomeRoute.history)
                                 },
                                 onAddSomething: { selectWorkoutPresented = true })
    }

    /// The hero intentionally focuses on one next action. When Coach has
    /// produced an eligible two-a-day, show the complete plan immediately
    /// below it instead of silently hiding the second modality.
    private var todayDualPlanCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Today's plan", systemImage: "calendar.badge.clock")
                .font(.headline)
            ForEach(coachDecision.todayPlannedRecommendations) { session in
                HStack(spacing: 10) {
                    Image(systemName: session.kind == .strength ? "dumbbell.fill" : "heart.fill")
                        .foregroundStyle(session.kind == .strength ? .green : .teal)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.title).font(.subheadline.weight(.semibold))
                        Text(session.subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Start") {
                        if session.kind == .strength, todaySuggestedPlan != nil {
                            openTodaySuggestion()
                        } else {
                            launchDecision(session)
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .accessibilityIdentifier("home.today.dual.\(session.id)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cadenceCard()
        .accessibilityIdentifier("home.today.dualPlan")
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
