import SwiftUI
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
    func prepareTodaySuggestion() {
        guard surface == .today,
              todaySuggestedPlan == nil,
              suggestedWorkoutPlan == nil,
              suggestedWorkoutTask == nil,
              sessions.filter({ $0.countsAsStrengthHistory }).count >= 2
        else { return }
        requestSuggestedStrength(present: false)
    }

    func generateTodaySuggestion(_ request: SuggestedWorkoutRequest) {
        suggestedWorkoutTask?.cancel()
        suggestedWorkoutTask = nil
        guard request.failureMessage == nil else { return }
        let task = Task {
            let option = await Task.detached(priority: .userInitiated) {
                SuggestedWorkoutGenerator.generatePersonalized(input: request.input)
            }.value
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard suggestedWorkoutTask != nil else { return }
                suggestedWorkoutTask = nil
                guard option.isLaunchable else { return }
                todaySuggestedPlan = SuggestedWorkoutPresenter.editablePlan(
                    for: option,
                    unit: request.unit,
                    warmupMinutes: request.warmupMinutes,
                    cooldownMinutes: request.cooldownMinutes)
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
