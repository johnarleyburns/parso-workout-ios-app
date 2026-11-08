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
        let dualRows = dualRecommendationRows
        if dualRows.isEmpty {
            todayHeroCard
            HomeTodayCardioCard(
                suggestion: todayCardio,
                isCalculating: todayCardioCalculating,
                hasNewer: pendingTodayCardio != nil,
                onStart: { launchSuggestedCardio($0) },
                onSuggestAnother: { suggestAnotherTodayCardio($0) },
                onShowNewer: { showNewerTodayCardio() })
        } else {
            HomeTodayRecommendationsCard(rows: dualRows, onStart: { launchDecision($0) })
        }
    }

    /// Rows for the compact dual card; empty keeps the existing hero. Only the
    /// normal generated recommendation is replaced: loading, in-progress,
    /// scheduled, recovery/pain, and completed-day states keep the hero.
    private var dualRecommendationRows: [TodayRecommendationRow] {
        let activity = cachedTodayHeroActivity
        guard coachSnapshotReady, activity.isLoaded, activity.completedWorkoutCount >= 2, resumeSession == nil,
              activity.todayScheduled == nil, activity.remainingScheduledToday == 0,
              activity.daySummary() == nil,
              coachDecision.primary.kind != .recovery, coachDecision.primary.kind != .rest
        else { return [] }
        return TodayRecommendationRowsPresenter.rows(
            slots: coachDecision.dailyRecommendationSlots,
            allowsTwoADays: settings.coachSchedulePreferences.allowsTwoADays)
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
            ? (coachSnapshotReady || restoredRecommendation != nil || todaySuggestedPlan != nil)
            : (restoredRecommendation != nil || todaySuggestedPlan != nil)
        let coachRecommendsStrength = pinnedRecommendation?.primaryIsStrength ?? (coachSnapshotReady
            ? coachDecision.primary.kind == .strength
            : false)
        // The personalized generator is intentionally asynchronous. Its compact
        // decision is a fallback only; a complete generated plan always wins.
        let coachFallback = pinnedRecommendation?.makeHero() ?? (coachSnapshotReady
            ? TodayHeroPresenter.recommendation(coachDecision)
            : nil)
        // A generated plan is the source of truth for both this hero and the
        // plan opened by Start.  Never substitute the compact one-exercise
        // coach fallback while a full plan is already available.
        let pairedPlan = (todaySuggestionIsStartupFallback || restoredRecommendation?.primaryIsStrength == true || coachRecommendsStrength)
            ? todaySuggestedPlan.map(TodaySuggestedPlanPayload.init)
            : nil
        let suggested = TodayStartupPresentation.hero(
            plan: pairedPlan,
            coachFallback: coachRecommendsStrength ? coachFallback : nil,
            reason: reason).map { hero in
                TodayHero(kind: hero.kind, title: hero.title,
                          estimatedMinutes: todaySuggestedPlan.flatMap { activity.suggestedDurationMinutes(plan: $0) },
                          exercises: hero.exercises, reason: hero.reason,
                          citationIDs: hero.citationIDs)
            }
        let starter = todaySuggestedPlan.map { plan in
            TodayHero(kind: .starter, title: plan.title,
                      estimatedMinutes: activity.suggestedDurationMinutes(plan: plan),
                      exercises: heroLines(plan),
                      reason: String(localized: "A general starter workout to get your first session going. It personalizes once you've logged a couple of workouts."),
                      citationIDs: SuggestedWorkoutPresenter.citationIDs)
        }
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
        case .suggested: todaySuggestionIsStartupFallback
            ? String(localized: "Starter strength workout")
            : String(localized: "Suggested Strength for You")
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
                                     path.append(HomeRoute.history)
                                 },
                                 onAddSomething: { selectWorkoutPresented = true })
        return VStack(alignment: .leading, spacing: 8) {
            heroCard
            if let pending = pendingSuggestedWorkoutPlan,
               hero.kind == .suggested || hero.kind == .starter || hero.kind == .restDay {
                Button("Show newer suggested workout…") {
                    todaySuggestedPlan = pending
                    todaySuggestionIsStartupFallback = false
                    pendingSuggestedWorkoutPlan = nil
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CadenceTheme.link)
                .accessibilityIdentifier("home.hero.newSuggestionBanner")
            }
            if showingSuggestedPlan, hero.kind == .suggested || hero.kind == .starter {
                Button("Suggest Another") { suggestAnotherTodayStrength() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CadenceTheme.link)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("home.hero.another")
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
