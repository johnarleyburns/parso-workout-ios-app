import SwiftUI
import CadenceCore
import CadenceFeatures

/// The "Suggest a workout" shortcut (Start Workout → Strength → Pick Workout)
/// reuses the muscle-coverage Fill the Gaps flow, so the shortcut and the
/// existing "Fill the gaps" button share one start boundary.
extension HomeView {
    /// The tracked muscle groups most behind this week.
    var fillGapMissingGroups: [MuscleGroup] {
        dashboard.volume
            .filter(\.isTracked)
            .sorted { $0.normalized == $1.normalized
                ? MuscleGroup.canonicalIndex($0.group) < MuscleGroup.canonicalIndex($1.group)
                : $0.normalized < $1.normalized }
            .prefix(3)
            .map(\.group)
    }

    @ViewBuilder
    var fillGapsQuickStart: some View {
        MuscleGroupQuickStartView(missing: fillGapMissingGroups) { session in
            _ = active.startStrength(session)
        }
    }

    func openFillGapsFromStartWorkout() {
        selectWorkoutPresented = false
        fillGapsPresented = true
    }
}
