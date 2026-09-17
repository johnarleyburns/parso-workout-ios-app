import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures
import os
/// Home dashboard.
struct HomeView: View {
    private static let performanceLog = OSLog(subsystem: "guru.parso.cladiron", category: "HomePerformance")
    @Environment(\.modelContext) var context
    @Environment(AppModel.self) var model
    @Environment(AppSettings.self) var settings
    @Environment(ActiveWorkoutModel.self) var active
    @Environment(ContributionCoordinator.self) var contributions
    @Environment(\.scenePhase) var scenePhase
    @Environment(\.cadenceModelContainer) var cadenceModelContainer
    @Query(sort: \WorkoutSession.date, order: .reverse) var sessions: [WorkoutSession]
    @Query(sort: \CardioWorkout.start, order: .reverse) var cardio: [CardioWorkout]
    @Query(sort: \Assessment.date, order: .reverse) var assessments: [Assessment]
    @Query(sort: \ReadinessEntry.date, order: .reverse) var readinessEntries: [ReadinessEntry]
    @Query(sort: [SortDescriptor(\ScheduledWorkout.scheduledDate),
                  SortDescriptor(\ScheduledWorkout.title)])
    var scheduledWorkouts: [ScheduledWorkout]
    @Query(filter: #Predicate<Exercise> { $0.isFavorite }, sort: \Exercise.name) var favoriteExercises: [Exercise]

    @State var logPickerPresented = false
    @State var selectWorkoutPresented = false
    @State var path = NavigationPath()
    @State var cardioType: CardioType?
    /// Explicit indoor/outdoor choice for distance-capable cardio. nil keeps
    /// the standalone recorder's legacy default for non-distance flows.
    @State var cardioTracksGPS: Bool?
    @State var outdoorType: CardioType?
    @State var otherCardioTitle: String?
    @State var intervalType: WorkoutType?
    @State var intervalLaunch: IntervalLaunch?
    @State var swimPresented = false
    @State var pending: PendingWorkout?
    @State var hrGateKind: PendingWorkout.Kind?
    @State var startWarmupAfterHRGate = false
    @State var warmupActive = false
    @State var today: DayActivity?
    @State var activityTrend: [DayActivity] = []
    @State var passiveSamples: [PassiveReadinessSample] = []
    @State var historyRefreshToken = UUID()
    @State var liveVolumeDelta: [MuscleGroup: Double] = [:]
    @State var timerCardioSetup: TimerCardioSetup?
    @State var pendingPlan: EditablePlan?
    @State var captureHR = false
    @State var cardioPickerPresented = false
    @State var weightsStartPresented = false
    @State var cardioGoalFor: CardioType?
    @State var warnAddOn: (session: CoachSession, status: CoachAddOnStatus)?
    @State var outdoorGoalMeters: Double?
    @State var showAlternatives = false
    @State var showSupport = false
    @State var pendingAddGapsDeficits: [MuscleGroup: Double]?
    @State var suggestionsExpanded = false
    @State var suggestedWorkoutCalculating = false
    @State var suggestedWorkoutFailure: String?
    /// Holds a request until the start sheet that launched it has finished
    /// dismissing, then opens the generated Personalized plan directly.
    @State var pendingSuggestedWorkoutRequest: SuggestedWorkoutRequest?
    @State var weeklyVolumeExpanded = false
    @State var coachIllustration = HomeCoachIllustration.random()
    @State var showWorkoutConflict = false
    @State var scheduledWorkoutBeingStarted: UUID?
    @State var confirmCancelPrevious = false
    @State var readinessPresented = false
    @State var coachSnapshot: HomeCoachSnapshot = .placeholder
    // Historical Home projections are cached separately from the coach
    // snapshot. Recomputing SwiftData relationships from the render path made
    // Home stutter whenever SwiftData published an unrelated change.
    @State var cachedWorkoutsTodayRows: [WorkoutsTodayPresenter.Row] = []
    @State var cachedWeekStrengthEntries: [TodayActivityPresenter.Entry] = []
    @State var cachedWeekCardioEntries: [TodayActivityPresenter.Entry] = []
    @State var cachedWeeklyVolumeKg = 0.0
    @State var cachedDashboard: HomeDashboardState?
    var dashboard: HomeDashboardState {
        if let cachedDashboard { return cachedDashboard }
        return makeDashboard()
    }
    func makeDashboard() -> HomeDashboardState {
        let snapshot = CoachSnapshot(facts: coachSnapshot.facts, coachFacts: coachSnapshot.coachFacts,
                                     insights: coachSnapshot.insights, recommendation: coachSnapshot.recommendation,
                                     decision: coachSnapshot.decision, plan: coachSnapshot.plan,
                                     behindPlan: coachSnapshot.behindPlan, addOn: coachSnapshot.addOn,
                                     readiness: coachSnapshot.readiness, optimizedPlan: coachSnapshot.optimizedPlan,
                                     engineObservation: coachSnapshot.engineObservation)
        return HomeDashboardPresenter.make(snapshot: snapshot,
                                           schedule: settings.coachSchedulePreferences,
                                           goal: settings.trainingGoal,
                                           experience: settings.experienceLevel,
                                           userAge: settings.userAge,
                                           liveVolumeDelta: liveVolumeDelta)
    }
    var coachFacts: TrainingFacts { coachSnapshot.facts }
    var coachInsights: [Insight] { coachSnapshot.insights }
    var coachRecommendation: Recommendation { coachSnapshot.recommendation }
    var coachDecision: CoachDecision { coachSnapshot.decision }
    var coachPlan: WeeklyPlan { coachSnapshot.plan }
    var passiveReadinessDisplay: PassiveReadinessPresenter.Display? {
        PassiveReadinessPresenter.display(for: coachSnapshot.readiness)
    }
    var todayReadiness: ReadinessEntry? {
        let calendar = Calendar.current
        return readinessEntries.first(where: { calendar.isDateInToday($0.date) })
    }
    @State var testCardOverride: TestRecommendation?
    @State var testCardDismissed = false
    var testRecommendation: TestRecommendation? {
        if testCardDismissed { return nil }
        if let override = testCardOverride { return override }
        return HomeCoachModel.testRecommendation(
            coachHidden: settings.coachHidden,
            assessments: assessments,
            lastRecommendedAt: settings.lastTestRecommendationAt,
            snoozedUntil: settings.testRecommendationSnoozes)
    }
    /// Gates coach recomputation. Deliberately keyed on coarse history counts + the
    /// refresh token + coach-relevant settings — NOT per-set session churn — so
    /// logging a set never re-runs the pipeline. The token is bumped when a workout
    /// completes (and on log / ingest / delete / day-change); counts catch
    /// create/delete; settings catch preference edits. The signature type + rule
    /// now live in `HomeCoachModel` where they are unit-tested.
    var coachSignature: HomeCoachModel.Signature {
        HomeCoachModel.signature(
            token: historyRefreshToken,
            sessions: sessions,
            cardio: cardio,
            assessments: assessments,
            readiness: readinessEntries,
            goal: settings.trainingGoal,
            experience: settings.experienceLevel,
            formula: settings.formula,
            schedule: settings.coachSchedulePreferences,
            profile: settings.coachPreferenceProfile,
            userAge: settings.userAge,
            overrideWeekKey: settings.coachPlanOverrideWeekKey)
    }
    func buildCoachSnapshot() async -> HomeCoachSnapshot {
        let signpostID = OSSignpostID(log: Self.performanceLog)
        os_signpost(.begin, log: Self.performanceLog, name: "coachExtractionAndBuild", signpostID: signpostID)
        defer { os_signpost(.end, log: Self.performanceLog, name: "coachExtractionAndBuild", signpostID: signpostID) }
        let policy: PlanningConstraintPolicy = settings.isPlanOverrideActive() ? .meetDeficits : .safe
        let computed: CoachSnapshot
        if let cadenceModelContainer {
            computed = await HomeCoachModel.snapshotAsync(
                container: cadenceModelContainer,
                goal: settings.trainingGoal,
                experience: settings.experienceLevel,
                formula: settings.formula,
                schedule: settings.coachSchedulePreferences,
                profile: settings.coachPreferenceProfile,
                passiveSamples: passiveSamples,
                userAge: settings.userAge,
                constraintPolicy: policy)
        } else {
            computed = await HomeCoachModel.snapshotAsync(
                sessions: sessions,
                cardio: cardio,
                assessments: assessments,
                readiness: readinessEntries,
                goal: settings.trainingGoal,
                experience: settings.experienceLevel,
                formula: settings.formula,
                schedule: settings.coachSchedulePreferences,
                profile: settings.coachPreferenceProfile,
                passiveSamples: passiveSamples,
                userAge: settings.userAge,
                constraintPolicy: policy)
        }
        let snapshot = HomeCoachSnapshot(computed)

        // Weekly coach plans are no longer a user-facing or Watch execution
        // surface. Widgets and the Watch receive only explicitly scheduled
        // workout records; do not recreate a hidden weekly plan on every Home
        // refresh. This also removes a large plan-payload build from the Home
        // refresh path.
        let todayScheduled = PlannedWorkoutsPresenter.today(
            scheduledWorkouts.map(HomePlannedWorkoutsSection.item))
        CadencePlatformSnapshotStore.save(CadenceTodaySnapshot(
            dayKey: Self.dayString(),
            planTitle: "Planned Workouts",
            sessionTitles: todayScheduled.map(\.title),
            readinessLabel: todayReadiness.map { ReadinessCheckInPresenter.summary(for: $0) },
            updatedAt: Date()))
        return snapshot
    }

    func refreshCoachSnapshot() async {
        guard !model.isRestoringCloudKitHistory else { return }
        model.coachRefreshInProgress = true
        defer { model.coachRefreshInProgress = false }
        coachSnapshot = await buildCoachSnapshot()
        liveVolumeDelta = [:]
        cachedDashboard = makeDashboard()
    }
    func handleInsightAction(_ action: Insight.Action) {
        switch action {
        case .addGapsToPlan(let deficits):
            pendingAddGapsDeficits = deficits
        case .revertToSafePlan:
            settings.coachPlanOverrideWeekKey = nil
            Haptics.selection()
        }
    }
    func confirmAddGaps() {
        Haptics.selection()
        settings.coachPlanOverrideWeekKey = AppSettings.weekKey(for: Date())
        pendingAddGapsDeficits = nil
    }

    @ViewBuilder
    var testRecommendationCard: some View {
        if let rec = testRecommendation {
            CoachTestRecommendationCard(
                recommendation: rec,
                onStart: { kind in
                    settings.lastTestRecommendationAt = Date()
                    testCardDismissed = true
                    path.append(HomeRoute.runAssessment(kind))
                },
                onPickDifferent: { pickDifferentTest() },
                onSnooze: { kind in snoozeTest(kind) })
        }
    }
    func pickDifferentTest() {
        let summaries = AssessmentMath.summaries(from: assessments)
        let inputs = CoachTestRecommendationEngine.Inputs(
            summaries: summaries,
            lastRecommendedAt: nil,   // ignore the weekly gate while cycling
            snoozedUntil: settings.testRecommendationSnoozes)
        let candidates = CoachTestRecommendationEngine.candidates(inputs)
        guard let current = testRecommendation else {
            testCardOverride = candidates.first
            return
        }
        if let idx = candidates.firstIndex(where: { $0.kind == current.kind }),
           idx + 1 < candidates.count {
            testCardOverride = candidates[idx + 1]
        } else {
            testCardOverride = candidates.first { $0.kind != current.kind } ?? current
        }
    }

    func snoozeTest(_ kind: AssessmentKind) {
        let until = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        var snoozes = settings.testRecommendationSnoozes
        snoozes[kind.rawValue] = until
        settings.testRecommendationSnoozes = snoozes
        settings.lastTestRecommendationAt = Date()
        testCardOverride = nil
        testCardDismissed = true
    }
    var addOnRecommendation: CoachAddOnRecommendation { coachSnapshot.addOn }
    static let headerDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEEMMMd")
        return f
    }()
    var headerDateText: String { Self.headerDateFormatter.string(from: .now) }
    /// Phase A (field-test-fixes): resume card from either in-memory active session
    /// or a persisted `isResumable` candidate the coach pipeline detects but
    /// ActiveWorkoutModel hasn't yet adopted.
    var resumeSession: WorkoutSession? {
        active.strengthSession ?? ActiveSessionRecovery.candidate(in: sessions)
    }

    var todayStrength: (hasStrength: Bool, exerciseNames: [String]) { TodayLogHelper.completedStrength(sessions: sessions) }
    var weeklyVolumeKg: Double {
        cachedWeeklyVolumeKg
    }
}

struct HomeCoachTaskIdentity: Equatable {
    let signature: HomeCoachModel.Signature
    let isRestoringCloudKitHistory: Bool
}

struct HomeActivityTaskIdentity: Equatable {
    let historyRefreshToken: UUID
    let sessionCount: Int
    let cardioCount: Int
}
