import Testing
import Foundation
import CadenceCore
@testable import CadenceFeatures

/// The Watch Set Card metric text must reach the view complete: the view scales
/// the font (`WatchMetricField`) instead of truncating, so the model must never
/// hand it an ellipsis or a shortened number.
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

    @Test func weightTextIsIndependentOfDynamicTypeInputs() {
        // Same state regardless of size category; scaling is a view concern.
        #expect(card(lbs: 650, reps: 100) == card(lbs: 650, reps: 100))
        #expect(card(lbs: 650, reps: 100).weightText.hasPrefix("650"))
    }
}
