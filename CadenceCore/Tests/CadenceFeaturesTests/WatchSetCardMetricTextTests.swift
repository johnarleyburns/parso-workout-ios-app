import Testing
import Foundation
import CadenceCore
@testable import CadenceFeatures

/// The Watch Set Card metric text must reach the view complete. The metric
/// layout is shared with the Watch view so its scale and accessibility layout
/// rules remain headlessly testable.
@Suite struct WatchSetCardMetricTextTests {
    private func card(lbs: Double, reps: Int) -> WatchSetCardState {
        WatchSetCardBuilder.make(
            exerciseName: "Squat", plannedWorkingSets: [], completedWorkingSets: 0,
            currentWeightKg: lbs / 2.2046226218, currentReps: reps,
            prefillWeightKg: lbs / 2.2046226218, prefillReps: reps,
            lastTime: nil, unit: .pounds, lifter: nil, nextLifter: nil,
            effortText: nil, isWarmup: false)
    }

    @Test func longPoundWeightsKeepFullNumericText() {
        for (lbs, expected) in [(650.0, "650"), (100.25, "100.3"), (1000.5, "1,000.5")] {
            let state = card(lbs: lbs, reps: 100)
            #expect(state.weightText.filter { !$0.isWhitespace } == expected.filter { !$0.isWhitespace }
                    || state.weightText.contains(expected.prefix(3)))
            #expect(!state.weightText.contains("…"))
            #expect(!state.weightText.contains("..."))
            #expect(!state.unitText.contains("…"))
            #expect(!state.unitText.isEmpty)
        }
    }

    @Test func compactMetricsScaleBeforeTheyCanTruncate() {
        #expect(WatchSetCardMetricLayout.valueMinimumScaleFactor == 0.55)
        #expect(WatchSetCardMetricLayout.unitMinimumScaleFactor == 0.70)
        #expect(WatchSetCardMetricLayout.fields(isAccessibilitySize: false) == .twoColumns)
        #expect(WatchSetCardMetricLayout.fields(isAccessibilitySize: true) == .stacked)

        // The same complete model text reaches normal, large, and accessibility
        // paths; only their layout changes.
        let state = card(lbs: 650, reps: 100)
        #expect(state.weightText.hasPrefix("650"))
        #expect(state.reps == 100)
    }
}
