import SwiftUI
import CadenceCore
import CadenceFeatures

/// The "Suggest a workout" shortcut (Start Workout → Strength → Pick Workout)
/// reuses the muscle-coverage Fill the Gaps flow, so the shortcut and the
/// existing "Fill the gaps" button share one start boundary.
extension HomeView {
    /// The tracked muscle groups most behind this week.
    var fillGapMissingGroups: HomeDashboardPresenter.GapTiers {
        HomeDashboardPresenter.gapTiers(from: dashboard.volume)
    }

    @ViewBuilder
    var fillGapsQuickStart: some View {
        MuscleGroupQuickStartView(tiers: fillGapMissingGroups) { session in
            _ = active.startStrength(session)
        } onPlan: { plan in
            workoutEditorPlan = plan
        }
    }

    func openFillGapsFromStartWorkout() {
        selectWorkoutPresented = false
        fillGapsPresented = true
    }
}
