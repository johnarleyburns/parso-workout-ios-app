import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

struct HomeTodaySuggestionTaskIdentity: Equatable {
    let historyRefreshToken: UUID
    let sessionCount: Int
    let isRestoringCloudKitHistory: Bool
}

extension HomeView {
    /// Prepares a value-only Today preview from the existing personalized
    /// generator. Starting or editing still goes through the normal editor.
    func prepareTodaySuggestion() async {
        guard surface == .today,
              todaySuggestedPlan == nil,
              suggestedWorkoutPlan == nil,
              suggestedWorkoutTask == nil,
              sessions.filter({ $0.countsAsStrengthHistory }).count >= 2
        else { return }
        // A valid same-day durable plan is restored before any catalog loading
        // or generation, so the prior personalized plan renders immediately.
        let earlyKey = todaySuggestionEarlyKey()
        if let restored = await HomeTodayCache.suggestionStore.restoreEarly(earlyKey: earlyKey) {
            guard !Task.isCancelled, todaySuggestedPlan == nil, suggestedWorkoutPlan == nil,
                  suggestedWorkoutTask == nil else { return }
            todaySuggestedPlan = restored.makePlan()
            return
        }
        // Cold generation is deferred past launch; heavy catalog mapping runs
        // off the main actor.
        if !(await HomeTodayCache.suggestionStore.hasSameDayEntry()) {
            try? await Task.sleep(for: .seconds(1.5))
        }
        guard !Task.isCancelled else { return }
        let candidates = await loadSuggestionCandidates()
        guard !Task.isCancelled, todaySuggestedPlan == nil, suggestedWorkoutPlan == nil,
              suggestedWorkoutTask == nil else { return }
        requestSuggestedStrength(present: false, preloadedCandidates: candidates)
    }

    /// Lightweight semantic key of everything that decides the Today plan,
    /// built without loading the exercise catalog.
    func todaySuggestionEarlyKey() -> String {
        let activeID = active.strengthSession?.id
        let history = sessions.filter { $0.id != activeID && $0.countsAsStrengthHistory }
            .map { "\($0.id)|\($0.date.timeIntervalSince1970)|\($0.endedAt?.timeIntervalSince1970 ?? 0)|\($0.completedOwnerWorkingSetCount)" }
            .sorted()
        let exclusions = ((try? ExerciseSuggestionExclusionStore.activeKeys(in: context)) ?? []).sorted()
        let catalogCount = (try? context.fetchCount(FetchDescriptor<Exercise>())) ?? -1
        let scheduled = scheduledWorkouts.map {
            "\($0.id)|\($0.scheduledDate.timeIntervalSince1970)|\($0.updatedAt.timeIntervalSince1970)|\($0.statusRaw)|\($0.payloadVersion)"
        }.sorted()
        return TodaySuggestedWorkoutEarlyKey.make([
            String(describing: settings.unit), "\(settings.warmupMinutes)", "\(settings.cooldownMinutes)",
            String(describing: settings.trainingGoal), String(describing: settings.preferredWorkoutStyle),
            String(describing: settings.experienceLevel),
            String(describing: settings.coachSchedulePreferences),
            "catalog:\(catalogCount)"
        ] + history.map { "h:" + $0 } + exclusions.map { "e:" + $0 } + scheduled.map { "x:" + $0 })
    }

    func generateTodaySuggestion(_ request: SuggestedWorkoutRequest) {
        suggestedWorkoutTask?.cancel()
        suggestedWorkoutTask = nil
        let generation = suggestedWorkoutGeneration.begin()
        guard request.failureMessage == nil else { return }
        // Stable semantic fingerprint: never the view refresh token or task ids.
        let fingerprint = TodaySuggestedWorkoutFingerprint.make(
            input: request.input,
            unitRaw: String(describing: request.unit),
            warmupMinutes: request.warmupMinutes,
            cooldownMinutes: request.cooldownMinutes,
            extras: scheduledWorkouts.map {
                "\($0.id)|\($0.scheduledDate.timeIntervalSince1970)|\($0.updatedAt.timeIntervalSince1970)|\($0.statusRaw)|\($0.payloadVersion)"
            })
        let store = HomeTodayCache.suggestionStore
        let earlyKey = todaySuggestionEarlyKey()
        let input = request.input
        let unit = request.unit
        let warmup = request.warmupMinutes
        let cooldown = request.cooldownMinutes
        let task = Task {
            // A durable hit returns without invoking the solver; concurrent
            // callers for the same day + fingerprint share one generation.
            let payload = await store.resolve(fingerprint: fingerprint, earlyKey: earlyKey) {
                let option = await Task.detached(priority: .userInitiated) {
                    SuggestedWorkoutGenerator.generatePersonalized(input: input)
                }.value
                guard option.isLaunchable else { return nil }
                return TodaySuggestedPlanPayload(SuggestedWorkoutPresenter.editablePlan(
                    for: option, unit: unit, warmupMinutes: warmup, cooldownMinutes: cooldown))
            }
            guard !Task.isCancelled, let payload else { return }
            await MainActor.run {
                guard suggestedWorkoutTask != nil,
                      suggestedWorkoutGeneration.accepts(generation) else { return }
                suggestedWorkoutTask = nil
                todaySuggestedPlan = payload.makePlan()
            }
        }
        suggestedWorkoutTask = task
    }

    func openTodaySuggestion() {
        guard let plan = todaySuggestedPlan else {
            requestSuggestedWorkout(.strength)
            return
        }
        todaySuggestedPlan = nil
        suggestedWorkoutPlan = plan
    }
}
