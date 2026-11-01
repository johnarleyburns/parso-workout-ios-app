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
        guard surface == .today, suggestedWorkoutPlan == nil, suggestedWorkoutTask == nil else { return }
        // Defer all history/catalog work until the cached hero is on screen
        // (bounded, so a missing cache cannot stall the suggestion).
        for _ in 0..<20 where !(coachSnapshotReady || restoredRecommendation != nil) && !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(50))
        }
        await Task.yield()
        guard !Task.isCancelled else { return }
        // Key + request are built on a background ModelContext; this actor only
        // publishes state and talks to the cache actor.
        guard let snapshot = await loadTodaySuggestionLaunchSnapshot(),
              !Task.isCancelled, snapshot.hasMinimumHistory else { return }
        let earlyKey = snapshot.earlyKey
        // A rendered plan whose key is proven current needs no further work.
        if todaySuggestedPlan != nil, todaySuggestionRenderedKey == earlyKey { return }
        // A valid same-day durable plan is restored before any generation.
        if let restored = await HomeTodayCache.suggestionStore.restoreEarly(earlyKey: earlyKey) {
            guard !Task.isCancelled, suggestedWorkoutPlan == nil, suggestedWorkoutTask == nil else { return }
            if todaySuggestedPlan == nil { todaySuggestedPlan = restored.makePlan() }
            todaySuggestionRenderedKey = earlyKey
            return
        }
        // Cold generation is deferred past launch. Any provisional plan stays
        // visible until the replacement is published.
        if !(await HomeTodayCache.suggestionStore.hasSameDayEntry()) {
            try? await Task.sleep(for: .seconds(1.5))
        }
        guard !Task.isCancelled, suggestedWorkoutPlan == nil, suggestedWorkoutTask == nil,
              let request = snapshot.request else { return }
        generateTodaySuggestion(SuggestedWorkoutRequest(request), earlyKey: earlyKey,
                                scheduledStamps: snapshot.scheduledStamps)
    }

    /// Builds the semantic key and generation request on a background
    /// `ModelContext`; only value DTOs cross back to the UI actor.
    func loadTodaySuggestionLaunchSnapshot() async -> TodaySuggestionLaunchSnapshot? {
        guard let container = cadenceModelContainer else { return nil }
        let settingsSnapshot = TodaySuggestionSettingsSnapshot(
            settings,
            historyIndexStorageURL: model.isUITestMode ? nil : ExerciseHistoryIndexStore.defaultStorageURL())
        let activeID = active.strengthSession?.id
        return await Task.detached(priority: .utility) {
            let context = ModelContext(container)
            return try? TodaySuggestionLaunchBuilder.load(
                in: context, activeSessionID: activeID, settings: settingsSnapshot)
        }.value
    }

    func generateTodaySuggestion(_ request: SuggestedWorkoutRequest, earlyKey: String,
                                 scheduledStamps: [String]) {
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
            extras: scheduledStamps)
        let store = HomeTodayCache.suggestionStore
        let snapshot = request.snapshot
        // Publish the exact snapshot the shared service consumes; never rebuilt during sync.
        model.updateWatchCoachSuggestion(WatchCoachSuggestionEnvelope.make(
            snapshot: snapshot, issuedAt: snapshot.generatedAt))
        let unit = request.unit
        let warmup = request.warmupMinutes
        let cooldown = request.cooldownMinutes
        let task = Task {
            // A durable hit returns without invoking the solver; concurrent
            // callers for the same day + fingerprint share one generation.
            let payload = await store.resolve(fingerprint: fingerprint, earlyKey: earlyKey) {
                let option = await Task.detached(priority: .userInitiated) {
                    CoachSuggestionService.generate(from: snapshot)
                }.value
                guard let option else { return nil }
                return TodaySuggestedPlanPayload(SuggestedWorkoutPresenter.editablePlan(
                    for: option, unit: unit, warmupMinutes: warmup, cooldownMinutes: cooldown))
            }
            guard !Task.isCancelled, let payload else { return }
            await MainActor.run {
                guard suggestedWorkoutTask != nil,
                      suggestedWorkoutGeneration.accepts(generation) else { return }
                suggestedWorkoutTask = nil
                todaySuggestedPlan = payload.makePlan()
                todaySuggestionRenderedKey = earlyKey
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

/// Watch `request_settings_sync` → rebuild the Coach snapshot through the normal builder path.
struct WatchCoachRefreshModifier: ViewModifier {
    let action: () -> Void
    func body(content: Content) -> some View {
        content.onReceive(NotificationCenter.default.publisher(for: .watchCoachSuggestionRefreshRequested)) { _ in
            action()
        }
    }
}

extension HomeView {
    func refreshWatchCoachSuggestion() {
        guard surface == .today, suggestedWorkoutTask == nil else { return }
        Task {
            guard let snapshot = await loadTodaySuggestionLaunchSnapshot(),
                  snapshot.hasMinimumHistory, let request = snapshot.request,
                  surface == .today, suggestedWorkoutTask == nil else { return }
            generateTodaySuggestion(SuggestedWorkoutRequest(request), earlyKey: snapshot.earlyKey,
                                    scheduledStamps: snapshot.scheduledStamps)
        }
    }
}
