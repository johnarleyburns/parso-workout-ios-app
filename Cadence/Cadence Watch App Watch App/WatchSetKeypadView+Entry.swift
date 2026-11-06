import SwiftUI
import CadenceCore
import CadenceFeatures

extension WatchSetKeypadView {
    var removableExercise: Exercise? {
        if case .keypad(let exercise) = model.stage { return exercise }
        return nil
    }

    func applyExactWeight(_ raw: String) {
        let increment = WeightIncrement(unit: model.unit)
        if case .success(let value) = WatchSetEntryParser.weight(raw, unit: model.unit, range: increment.range) {
            model.currentWeightDisplay = value
            WatchHaptics.success()
        }
    }

    func applyExactReps(_ raw: String) {
        if case .success(let value) = WatchSetEntryParser.reps(raw) {
            model.currentReps = Double(value)
            WatchHaptics.success()
        }
    }
}
