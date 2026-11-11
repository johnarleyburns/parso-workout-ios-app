import SwiftUI
import CadenceCore
import CadenceFeatures

/// Wiring for the dismissible Strength suggestion preview. All transitions
/// live in `SuggestedStrengthPreviewState`; this only performs its effects.
extension HomeView {
    func suggestedStrengthHooks(for plan: EditablePlan) -> SuggestedStrengthEditorHooks {
        SuggestedStrengthEditorHooks(
            isRegenerating: suggestedStrengthPreview.isRegenerating,
            message: suggestedStrengthPreview.unavailableMessage,
            onStart: { edited in
                suggestedStrengthPreview.editedPlan = edited
                handleSuggestedStrength(.start)
            },
            onScheduled: { handleSuggestedStrength(.scheduleSucceeded) },
            onSuggestAnother: { edited in
                suggestedStrengthPreview.editedPlan = edited
                handleSuggestedStrength(.suggestAnother)
            },
            onCancel: { handleSuggestedStrength(.cancel) })
    }

    func handleSuggestedStrength(_ action: SuggestedStrengthAction) {
        if case .scheduleSucceeded = action, !suggestedStrengthPreview.isSchedulePresented {
            // The editor presents scheduling itself; mark it so the reducer accepts success.
            _ = suggestedStrengthPreview.reduce(.schedule)
        }
        let effect = suggestedStrengthPreview.reduce(action)
        perform(suggestedStrengthEffect: effect)
    }

    private func perform(suggestedStrengthEffect effect: SuggestedStrengthEffect) {
        switch effect {
        case .none:
            break
        case .dismissThenStart(let plan):
            suggestedWorkoutPlan = nil
            Task { @MainActor in
                await Task.yield()
                handleEditorStart(plan)
            }
        case .dismissAfterSchedule:
            suggestedWorkoutPlan = nil
        case .cancelPresentation:
            suggestedStrengthAlternativeTask?.cancel()
            suggestedStrengthAlternativeTask = nil
            suggestedWorkoutPlan = nil
        case .requestAlternative(let keys, let token):
            requestStrengthAlternative(excluding: keys, token: token)
        }
    }

    private func requestStrengthAlternative(excluding keys: Set<String>, token: UUID) {
        suggestedStrengthAlternativeTask?.cancel()
        let known = suggestedStrengthRequest
        suggestedStrengthAlternativeTask = Task { @MainActor in
            var base = known
            if base == nil {
                base = await loadTodaySuggestionLaunchSnapshot()?.request
            }
            guard !Task.isCancelled else { return }
            guard let base else {
                _ = suggestedStrengthPreview.reduce(.replacementUnavailable(token: token))
                return
            }
            let request = SuggestedStrengthAlternative.request(from: base, excludingKeys: keys)
            let snapshot = CoachSuggestionSnapshotBuilder.make(
                request: request, generatedAt: request.input.engineContext?.asOf ?? Date())
            let option = await Task.detached(priority: .userInitiated) {
                CoachSuggestionService.generate(from: snapshot)
            }.value
            guard !Task.isCancelled else { return }
            suggestedStrengthAlternativeTask = nil
            if let option {
                let plan = SuggestedWorkoutPresenter.editablePlan(
                    for: option, unit: request.unit,
                    warmupMinutes: request.warmupMinutes, cooldownMinutes: request.cooldownMinutes)
                let before = suggestedStrengthPreview.plan
                _ = suggestedStrengthPreview.reduce(.replacementSucceeded(plan, token: token))
                if suggestedStrengthPreview.plan == plan, before != plan {
                    suggestedStrengthRequest = request
                    suggestedWorkoutPlan = plan
                }
            } else {
                _ = suggestedStrengthPreview.reduce(.replacementUnavailable(token: token))
            }
        }
    }
}
